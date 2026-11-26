import Foundation
import Testing
@testable import PocketAgentCore

@Suite("Local-only developer route")
struct LocalControlPacketTests {
    private func packet() -> Data {
        var bytes = [UInt8](repeating: 0, count: 40)
        bytes[0] = 0x45
        bytes[3] = 40
        bytes[6] = 0x40
        bytes[8] = 64
        bytes[9] = 6
        bytes.replaceSubrange(12..<20, with: [10, 7, 0, 0, 10, 7, 0, 1])
        bytes[20] = 0xc0
        bytes[21] = 0x01
        bytes[22] = 0xc0
        bytes[32] = 0x50
        bytes[33] = 2
        return Data(bytes)
    }

    @Test func reflectsOnlyAddressPair() throws {
        let original = packet()
        let output = try #require(LocalControlPacket.reflected(original))
        #expect(Array(output[12..<20]) == [10, 7, 0, 1, 10, 7, 0, 0])
        #expect(output.prefix(12) == original.prefix(12))
        #expect(output.suffix(from: 20) == original.suffix(from: 20))
        func sum(_ bytes: Data) -> Int {
            stride(from: 0, to: bytes.count, by: 2).reduce(0) { $0 + (Int(bytes[$1]) << 8 | Int(bytes[$1 + 1])) }
        }
        #expect(sum(output) == sum(original))
    }

    @Test func rejectsOtherAddressesAndProtocols() {
        for (offset, value) in [(12, 192), (15, 2), (19, 2), (9, 17), (0, 0x65)] {
            var changed = packet()
            changed[offset] = UInt8(value)
            #expect(LocalControlPacket.reflected(changed) == nil)
        }
    }

    @Test func rejectsTruncationFragmentsAndInvalidHeaders() {
        let original = packet()
        for count in 0..<original.count {
            #expect(LocalControlPacket.reflected(original.prefix(count)) == nil)
        }
        for (offset, value) in [(0, 0x44), (0, 0x4f), (3, 39), (6, 0x20), (7, 1), (32, 0x40), (32, 0xf0)] {
            var changed = original
            changed[offset] = UInt8(value)
            #expect(LocalControlPacket.reflected(changed) == nil)
        }
    }

    @Test func doesNotReflectItsOwnInboundPacketAgain() throws {
        let inbound = try #require(LocalControlPacket.reflected(packet()))
        #expect(LocalControlPacket.reflected(inbound) == nil)
    }
}
