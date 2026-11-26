import Foundation
import XCTest
@testable import RorkDevice

final class PocketControlProbeTests: XCTestCase {
    func testDeadlineClosesAllOpenedSocketsAndRejectsLateSockets() throws {
        let lease = PocketControlProbeLease()
        let first = FakeConnection(inbound: Data())
        let second = FakeConnection(inbound: Data())
        try lease.register(first)
        try lease.register(second)
        lease.close()
        lease.close()
        XCTAssertTrue(first.isClosed)
        XCTAssertTrue(second.isClosed)
        let late = FakeConnection(inbound: Data())
        XCTAssertThrowsError(try lease.register(late))
        XCTAssertTrue(late.isClosed)
    }

    func testAdvertisedServicesDoNotOpenAnInputService() async throws {
        let transport = try fixture(device: "our-phone", services: [
            "com.apple.coredevice.hid.universalhidservice",
            "com.apple.coredevice.appservice",
            "com.apple.coredevice.displayservice"
        ])
        let capabilities = try await PocketControlProbe.inspect(
            transport: transport, discoveryPort: 51000, expectedDeviceIdentifier: "our-phone"
        )
        XCTAssertTrue(capabilities.universalHID)
        XCTAssertTrue(capabilities.appService)
        XCTAssertEqual(capabilities.displayServices, ["com.apple.coredevice.displayservice"])
        XCTAssertEqual(transport.ports, [51000])
        XCTAssertTrue(transport.connection.isClosed)
    }

    func testMissingHIDIsNotReportedAsWorkingControl() async throws {
        let transport = try fixture(device: "our-phone", services: ["com.apple.coredevice.appservice"])
        let capabilities = try await PocketControlProbe.inspect(
            transport: transport, discoveryPort: 51000, expectedDeviceIdentifier: "our-phone"
        )
        XCTAssertFalse(capabilities.universalHID)
        XCTAssertEqual(transport.ports, [51000])
        XCTAssertTrue(transport.connection.isClosed)
    }

    func testDifferentDeviceIsRejectedAndConnectionClosed() async throws {
        let transport = try fixture(device: "another-phone", services: [])
        do {
            _ = try await PocketControlProbe.inspect(
                transport: transport, discoveryPort: 51000, expectedDeviceIdentifier: "our-phone"
            )
            XCTFail("Must not accept another device")
        } catch {
            XCTAssertEqual(transport.ports, [51000])
            XCTAssertTrue(transport.connection.isClosed)
        }
    }

    private func fixture(device: String, services: [String]) throws -> ProbeTransport {
        var inbound = try remoteXPCSessionHandshakeInbound()
        let directory = Dictionary(uniqueKeysWithValues: services.enumerated().map { index, name in
            (name, RemoteXPCValue.dictionary(["Port": .string(String(51001 + index))]))
        })
        let message = try RemoteXPCMessageCodec.encode(
            value: .dictionary([
                "MessageType": .string("Handshake"),
                "Properties": .dictionary(["UniqueDeviceID": .string(device)]),
                "Services": .dictionary(directory)
            ]), flags: 0x101, messageIdentifier: 1
        )
        inbound.append(remoteXPCTestFrame(type: 0, streamIdentifier: 1, payload: message))
        return ProbeTransport(connection: FakeConnection(inbound: inbound))
    }
}

private final class ProbeTransport: DeviceTransport {
    let connection: FakeConnection
    var ports: [UInt16] = []
    init(connection: FakeConnection) { self.connection = connection }
    func connect(to port: UInt16) async throws -> DeviceConnection {
        ports.append(port)
        return connection
    }
}
