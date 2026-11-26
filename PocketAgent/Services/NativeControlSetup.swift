import Combine
import Darwin
import Foundation
import Network
import RorkDevice
import SwiftUI

/// Admission test only: no XCTest calls, input events or runner shutdown.
/// A successful connection is not evidence of successful screen control.
@MainActor
final class NativeControlSetup: ObservableObject {
    @Published private(set) var status = "Experimental replacement connection. The current helper and its running icon are unchanged."
    @Published private(set) var busy = false
    @Published private(set) var details = ""
    private var operation: Task<Void, Never>?

    func cancel() { operation?.cancel() }

    // Personal-device prototype. Must match the device used for explicit trust.
    private let expectedDevice = "00008150-000A20360212401C"
    private var identityURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("PocketControl/remote-pairing.plist")
    }

    func check(localRoute: Bool = false) {
        guard !busy else { return }
        busy = true
        details = ""
        status = "Checking this iPhone's developer-service routes. No taps will be sent."
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                guard FileManager.default.fileExists(atPath: identityURL.path) else {
                    status = "New developer pairing has not been provisioned yet. The existing helper is unchanged."
                    return
                }
                try FileManager.default.setAttributes([
                    .protectionKey: FileProtectionType.complete,
                    .posixPermissions: 0o600
                ], ofItemAtPath: identityURL.path)
                var protectedURL = identityURL
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                try protectedURL.setResourceValues(resourceValues)
                let identity = try RemotePairingIdentity(contentsOf: identityURL)
                var failures: [String] = []
                for host in localRoute ? [LocalControlPacket.peerAddress] : Self.ownAddresses() {
                    try Task.checkCancellation()
                    status = "Checking \(host):49152… No input is being sent."
                    guard await Self.canConnect(host) else {
                        failures.append("\(host): not reachable")
                        continue
                    }
                    do {
                        let tunnel = try await PocketControlProbe.connect(to: host, using: identity)
                        let network: CoreDeviceUserspaceNetwork
                        do { network = try CoreDeviceUserspaceNetwork(tunnel: tunnel) }
                        catch { tunnel.close(); throw error }
                        defer { network.close() }
                        let discoveryDeadline = Task {
                            do { try await Task.sleep(for: .seconds(10)); network.close() }
                            catch { }
                        }
                        defer { discoveryDeadline.cancel() }
                        let capabilities = try await PocketControlProbe.inspect(
                            transport: network,
                            discoveryPort: network.configuration.serviceDiscoveryPort,
                            expectedDeviceIdentifier: expectedDevice
                        )
                        status = "Authenticated directly from this iPhone.\nTouch service: \(capabilities.universalHID ? "available" : "missing")\nApp service: \(capabilities.appService ? "available" : "missing")\n\(capabilities.displayServices.joined(separator: "\n"))\nConnection test only; control and overlay removal are not yet verified."
                        saveDiagnostic()
                        return
                    } catch {
                        try Task.checkCancellation()
                        failures.append("\(host): \(error.localizedDescription)")
                    }
                }
                details = failures.joined(separator: "\n")
                status = "Pairing is provisioned, but a direct connection from this iPhone could not authenticate. The current helper and running icon are unchanged."
            } catch is CancellationError {
                status = "Connection check cancelled. No input was sent."
            } catch {
                status = "Connection setup failed: \(error.localizedDescription)"
            }
            saveDiagnostic()
        }
    }

    private func saveDiagnostic() {
        // No identity/key serialization, screenshots or screen contents.
        let url = URL.applicationSupportDirectory.appendingPathComponent("PocketControl/connection-result.txt")
        try? (status + "\n" + details).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func ownAddresses() -> [String] {
        var result = ["127.0.0.1", "::1"]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = item.pointee
            guard Int32(interface.ifa_flags) & IFF_UP != 0,
                  let addr = interface.ifa_addr,
                  (addr.pointee.sa_family == UInt8(AF_INET) || addr.pointee.sa_family == UInt8(AF_INET6)),
                  (String(cString: interface.ifa_name) == "en0" || String(cString: interface.ifa_name).hasPrefix("utun")) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buffer,
                           socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let address = String(cString: buffer)
                if !result.contains(address) { result.append(address) }
            }
        }
        return result
    }

    private static func canConnect(_ host: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: 49152, using: .tcp)
            let queue = DispatchQueue(label: "pocket.native-control.probe")
            let completion = NativeProbeCompletion(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: completion.finish(true)
                case .failed: completion.finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) { completion.finish(false) }
        }
    }
}

/// Both the timeout and the connection callback may finish the same probe.
private final class NativeProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Bool, Never>

    init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ success: Bool) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        lock.unlock()
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(returning: success)
    }
}

struct NativeControlSetupSection: View {
    @StateObject private var setup = NativeControlSetup()
    @StateObject private var route = LocalControlRoute.shared

    var body: some View {
        Section {
            DisclosureGroup("Native replacement · experimental") {
                NavigationLink("Native engine test…") {
                    NativeControlRouteView(setup: setup, route: route)
                }
                Text("Native touch and Settings launch are verified without XCTest. Chat screen tools now use this engine with per-step approval. The controls here are separate developer diagnostics; stop them before using the agent.")
                    .font(.footnote)
                Text(setup.status).font(.footnote).textSelection(.enabled)
                Button("Verify new developer connection") { setup.check() }
                    .disabled(setup.busy)
                if !setup.details.isEmpty {
                    DisclosureGroup("Connection diagnostics") {
                        Text(setup.details).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Text("Uses the separately approved Pocket Agent Native Control identity. This read-only check cannot tap, stop the helper or remove its icon. It does not activate a replacement engine.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Push within the existing navigation stack. Presenting a second sheet from
/// a lazy Form section can lose its presenter and dismiss both test panels.
private struct NativeControlRouteView: View {
    @ObservedObject var setup: NativeControlSetup
    @ObservedObject var route: LocalControlRoute
    @StateObject private var native = NativeControlModel.shared

    var body: some View {
                Form {
                    Section("Local-only replacement route") {
                        Text(route.status).font(.footnote)
                        HStack {
                            Button("Start local route", action: route.installAndStart)
                                .disabled(route.busy || route.connected || setup.busy)
                            Spacer()
                            Button("Stop", role: .destructive) { setup.cancel(); native.stop(); route.stop() }
                                .disabled(!route.connected)
                        }.buttonStyle(.borderless)
                        Text("Local only · 2 minutes · temporarily replaces Tailscale/Ollama.").font(.caption).foregroundStyle(.secondary)
                    }
                    NativeEngineTestSection(native: native, routeConnected: route.connected)
                    Section("Connection result · no taps") {
                        Button("Verify paired native services") { setup.check(localRoute: true) }
                            .disabled(!route.connected || setup.busy)
                        Text(setup.status).font(.footnote).textSelection(.enabled)
                        if !setup.details.isEmpty { Text(setup.details).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                    Section {
                        Text("The local route temporarily replaces Tailscale. The approved home-Wi-Fi model connection works without Tailscale. Keep the legacy XCTest helper stopped: starting it brings back Automation Running.")
                        Link("Routing technique based on LocalDevVPN · StephenDev0 / Stossy11 / SideStore", destination: URL(string: "https://github.com/StephenDev0/LocalDevVPN")!)
                    }.font(.footnote)
                }
                .navigationTitle("Native Control Test")
                .navigationBarTitleDisplayMode(.inline)
                .onChange(of: route.connected) { _, connected in if !connected { native.stop() } }
    }
}
