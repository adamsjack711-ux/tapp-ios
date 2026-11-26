import ArgumentParser
import Foundation
import RorkDevice

/// Read-only comparison of direct network pairing with the USB enrollment path.
struct PocketControlDirectProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pocket-probe")
    @Option var host: String
    @Option var identity: String
    @Option var udid: String
    @Flag(help: "Read one native screenshot; print its byte count only, never save its contents.")
    var screenshot = false
    @Flag(help: "Read HID surface metadata only; sends no input and creates no devices.")
    var pointerInventory = false

    func run() async throws {
        let credential = try RemotePairingIdentity(contentsOf: URL(fileURLWithPath: identity))
        if pointerInventory {
            let engine = try await PocketNativeEngine.connect(host: host, identity: credential, expectedDevice: udid)
            do {
                print(try await engine.pointerInventory())
                await engine.close()
            } catch { await engine.close(); throw error }
            return
        }
        if screenshot {
            let engine = try await PocketNativeEngine.connect(host: host, identity: credential, expectedDevice: udid)
            print("Native engine authenticated; requesting screenshot.")
            do {
                let image = try await engine.screenshot()
                print("Native PNG received: \(image.count) bytes (not saved)")
                await engine.close()
            } catch { await engine.close(); throw error }
            return
        }
        let tunnel = try await RemotePairingTunnel.connect(
            to: host, using: credential, requestedMaximumTransmissionUnit: 1280, timeout: .seconds(5)
        )
        defer { tunnel.close() }
        let network = try CoreDeviceUserspaceNetwork(tunnel: tunnel)
        defer { network.close() }
        let capabilities = try await PocketControlProbe.inspect(
            transport: network, discoveryPort: network.configuration.serviceDiscoveryPort,
            expectedDeviceIdentifier: udid
        )
        print("Authenticated; HID advertised: \(capabilities.universalHID); app service: \(capabilities.appService)")
    }
}
