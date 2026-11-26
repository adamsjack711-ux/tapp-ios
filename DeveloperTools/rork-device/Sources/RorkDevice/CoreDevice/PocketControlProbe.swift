import Foundation

/// A deliberately read-only admission test for Pocket Agent's replacement
/// control transport. It never opens XCTest or sends input events.
public struct PocketControlCapabilities: Sendable {
    public let deviceIdentifier: String
    public let universalHID: Bool
    public let appService: Bool
    public let displayServices: [String]
}

public enum PocketControlProbe {
    #if canImport(BigInt)
    /// Bound the entire authentication exchange, not just TCP connection setup.
    /// The watchdog closes every opened socket to unblock non-cancellable reads.
    public static func connect(to host: String, using identity: RemotePairingIdentity) async throws -> RemotePairingTunnel {
        let lease = PocketControlProbeLease()
        let transport = PocketControlProbeTransport(base: try RemotePairingTransportProvider.makeDefault(), lease: lease)
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(15)); lease.close() }
            catch { /* Normal completion cancels the deadline. */ }
        }
        defer { watchdog.cancel() }
        return try await withTaskCancellationHandler {
            try await RemotePairingTunnel.connect(
                to: host, using: identity, requestedMaximumTransmissionUnit: 1280,
                timeout: .seconds(5), transport: transport
            )
        } onCancel: { lease.close() }
    }
    #endif

    public static func inspect(
        transport: any DeviceTransport,
        discoveryPort: UInt16,
        expectedDeviceIdentifier: String
    ) async throws -> PocketControlCapabilities {
        let connection = try await transport.connect(to: discoveryPort)
        let discovery = try await RemoteServiceDiscoverySession.open(over: connection)
        defer { discovery.close() }
        let directory = discovery.directory
        guard directory.deviceIdentifier == expectedDeviceIdentifier else {
            throw RorkDeviceError.invalidInput("The connection reached a different device. No control service was opened.")
        }
        return PocketControlCapabilities(
            deviceIdentifier: expectedDeviceIdentifier,
            universalHID: directory.services["com.apple.coredevice.hid.universalhidservice"] != nil,
            appService: directory.services["com.apple.coredevice.appservice"] != nil,
            displayServices: directory.services.keys.filter {
                $0.contains("display") || $0.contains("screen") || $0.contains("media")
            }.sorted()
        )
    }
}

/// Shared only between the deadline callback and connection setup.
final class PocketControlProbeLease: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [DeviceConnection] = []
    private var closed = false

    func register(_ connection: DeviceConnection) throws {
        lock.lock()
        if closed {
            lock.unlock()
            connection.close()
            throw RorkDeviceError.invalidInput("Native connection check timed out or was cancelled.")
        }
        connections.append(connection)
        lock.unlock()
    }

    func close() {
        lock.lock()
        closed = true
        let pending = connections
        connections.removeAll()
        lock.unlock()
        pending.forEach { $0.close() }
    }
}

#if canImport(BigInt)
private struct PocketControlProbeTransport: RemotePairingTransport {
    let base: any RemotePairingTransport
    let lease: PocketControlProbeLease

    func openControlConnection(to host: String, port: UInt16, over route: RemotePairingTransportRoute, timeout: Duration) async throws -> DeviceConnection {
        let connection = try await base.openControlConnection(to: host, port: port, over: route, timeout: timeout)
        try lease.register(connection)
        return connection
    }

    func openTLSConnection(to host: String, port: UInt16, using preSharedKey: Data, over route: RemotePairingTransportRoute, timeout: Duration) async throws -> RemotePairingTLSConnection {
        let stream = try await base.openTLSConnection(to: host, port: port, using: preSharedKey, over: route, timeout: timeout)
        try lease.register(stream.connection)
        return stream
    }
}
#endif
