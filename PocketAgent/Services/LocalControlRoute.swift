import Combine
import Foundation
import NetworkExtension

@MainActor
final class LocalControlRoute: ObservableObject {
    static let shared = LocalControlRoute()
    static let providerID = "com.jackadamslovell.PocketAgent.LocalControl"
    @Published private(set) var status = "Not connected"
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var startTask: Task<Void, Never>?
    private var stopRequested = false

    init() {
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        Task { await loadExisting() }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func loadExisting() async {
        do {
            manager = try await NETunnelProviderManager.loadAllFromPreferences().first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerID
            }
            refreshStatus()
        } catch { status = "Could not load local route: \(error.localizedDescription)" }
    }

    /// Saving for the first time asks the owner for iOS VPN permission.
    func installAndStart() {
        guard !busy, !connected else { return }
        busy = true
        startTask = Task {
            defer { busy = false }
            do {
                await loadExisting()
                try Task.checkCancellation()
                let selected = manager ?? NETunnelProviderManager()
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = Self.providerID
                configuration.serverAddress = "On-device developer route"
                configuration.disconnectOnSleep = true
                configuration.includeAllNetworks = false
                configuration.excludeLocalNetworks = false
                selected.protocolConfiguration = configuration
                selected.localizedDescription = "hitapp · Local Control Test"
                selected.isOnDemandEnabled = false
                selected.onDemandRules = []
                selected.isEnabled = true
                manager = selected
                status = "Approve the VPN prompt on your iPhone. This may disconnect Tailscale."
                try await selected.saveToPreferences()
                try await selected.loadFromPreferences()
                try Task.checkCancellation()
                try selected.connection.startVPNTunnel()
                refreshStatus()
            } catch { status = "Local route not started: \(error.localizedDescription)" }
        }
    }

    func stop() {
        stopRequested = true
        startTask?.cancel()
        manager?.connection.stopVPNTunnel()
        refreshStatus()
    }

    func restartAndWait() async throws {
        await loadExisting()
        stop()
        try await startAndWait()
    }

    func startAndWait() async throws {
        // stopVPNTunnel is asynchronous. A stale .connected notification must
        // not let the next operation use the route that is being torn down.
        if stopRequested || manager?.connection.status == .disconnecting {
            for _ in 0..<120 {
                try Task.checkCancellation()
                refreshStatus()
                if manager == nil || manager?.connection.status == .disconnected || manager?.connection.status == .invalid {
                    stopRequested = false
                    break
                }
                try await Task.sleep(for:.milliseconds(100))
            }
            guard !stopRequested, manager?.connection.status != .disconnecting else {
                throw RouteError.failed("The previous local route is still stopping. No input was sent.")
            }
        }
        refreshStatus()
        if connected { return }
        installAndStart()
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(100))
            if connected { return }
            if !busy, manager?.connection.status != .connecting, manager?.connection.status != .reasserting {
                throw RouteError.failed(status)
            }
        }
        stop()
        throw RouteError.failed("The local control route did not connect in time.")
    }

    private enum RouteError: LocalizedError {
        case failed(String)
        var errorDescription: String? { switch self { case .failed(let message): return message } }
    }

    private func refreshStatus() {
        connected = manager?.connection.status == .connected
        switch manager?.connection.status {
        case .connected: status = "Local route connected · automatically stops after 2 minutes"
        case .connecting, .reasserting: status = "Connecting local route…"
        case .disconnecting: status = "Stopping local route…"
        case .disconnected: status = "Local route stopped. The approved home-Wi-Fi model route remains available."
        default: status = "Local route not installed"
        }
    }
}
