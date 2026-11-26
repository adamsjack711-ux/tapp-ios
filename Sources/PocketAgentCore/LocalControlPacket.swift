import Foundation

/// Local packet reflection for the explicitly approved developer connection.
/// No internet forwarding, DNS interception, remote gateway, or packet logging.
/// Routing technique based on LocalDevVPN (StephenDev0 / Stossy11 / SideStore).
public enum LocalControlPacket {
    public static let deviceAddress = "10.7.0.0"
    public static let peerAddress = "10.7.0.1"

    public static func reflected(_ packet: Data) -> Data? {
        let bytes = [UInt8](packet)
        guard bytes.count >= 40, bytes[0] >> 4 == 4 else { return nil }
        let headerLength = Int(bytes[0] & 15) * 4
        let totalLength = Int(bytes[2]) << 8 | Int(bytes[3])
        guard headerLength >= 20, totalLength == bytes.count,
              totalLength >= headerLength + 20,
              bytes[9] == 6, // TCP only; pairing negotiates a second dynamic TCP port.
              bytes[6] & 0x3f == 0, bytes[7] == 0, // No fragments.
              Array(bytes[12..<16]) == [10, 7, 0, 0],
              Array(bytes[16..<20]) == [10, 7, 0, 1] else { return nil }
        let tcpHeaderLength = Int(bytes[headerLength + 12] >> 4) * 4
        guard tcpHeaderLength >= 20, headerLength + tcpHeaderLength <= totalLength else { return nil }
        var reflected = bytes
        reflected.replaceSubrange(12..<16, with: bytes[16..<20])
        reflected.replaceSubrange(16..<20, with: bytes[12..<16])
        // Swapping the complete address pair preserves both the IPv4 header
        // checksum and the TCP pseudoheader checksum. Payload is never changed.
        return Data(reflected)
    }
}
