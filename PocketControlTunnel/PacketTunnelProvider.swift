import Foundation
import NetworkExtension

/// Only a local networking route, not an input engine or a public VPN service.
/// Based on LocalDevVPN's packet-reflection technique; see THIRD_PARTY_NOTICES.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let work = DispatchQueue(label: "pocket.local-control.route")
    private var running = false
    private var expiry: DispatchWorkItem?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: LocalControlPacket.deviceAddress)
        let ipv4 = NEIPv4Settings(addresses: [LocalControlPacket.deviceAddress], subnetMasks: ["255.255.255.0"])
        // Only one synthetic local peer. Do not capture internet, LAN, DNS, or IPv6.
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: LocalControlPacket.peerAddress, subnetMask: "255.255.255.255")]
        ipv4.excludedRoutes = [.default()]
        settings.ipv4Settings = ipv4
        settings.mtu = 1280
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self, error == nil else { completionHandler(error); return }
            self.work.async { [self] in
                self.running = true
                self.readNextBatch()
                // Admission test is bounded, even if the app crashes/backgrounds.
                let expiry = DispatchWorkItem { [weak self] in
                    guard let self, self.running else { return }
                    self.running = false
                    self.cancelTunnelWithError(nil)
                }
                self.expiry = expiry
                self.work.asyncAfter(deadline: .now() + 120, execute: expiry)
                completionHandler(nil)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        work.async {
            self.running = false
            self.expiry?.cancel()
            self.expiry = nil
            completionHandler()
        }
    }

    private func readNextBatch() {
        guard running else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            self.work.async {
                guard self.running else { return }
                var reflected: [Data] = []
                for (packet, family) in zip(packets, protocols) where family.int32Value == AF_INET {
                    if let result = LocalControlPacket.reflected(packet) { reflected.append(result) }
                }
                if !reflected.isEmpty {
                    self.packetFlow.writePackets(reflected, withProtocols: Array(repeating: NSNumber(value: AF_INET), count: reflected.count))
                }
                self.readNextBatch()
            }
        }
    }
}
