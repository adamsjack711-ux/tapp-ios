import Foundation

/// Fixed developer navigation gestures. No model-supplied coordinates.
public enum PocketNavigationGesture: Sendable, CaseIterable {
    case home, appSwitcher, pageLeft, pageRight
    var homeButtonPressCount: Int {
        switch self {
        case .home: 1
        case .appSwitcher: 2
        case .pageLeft, .pageRight: 0
        }
    }
    var start: (Double, Double) {
        switch self {
        case .home, .appSwitcher: (0.5, 0.995)
        case .pageLeft: (0.8, 0.55)
        case .pageRight: (0.2, 0.55)
        }
    }
    var end: (Double, Double) {
        switch self {
        case .home, .appSwitcher: (0.5, 0.45)
        case .pageLeft: (0.2, 0.55)
        case .pageRight: (0.8, 0.55)
        }
    }
    var holdMilliseconds: Int { self == .appSwitcher ? 600 : 0 }
}

/// Wire encoders for the user-approved CoreDevice prototype. Protocol facts
/// documented by pymobiledevice3; no Python runtime or XCTest dependency.
enum PocketNativeWire {
    /// Fixed Consumer/Menu (Home) event. No arbitrary button usages are exposed.
    /// Wire state is 1/2, not the Swift HIDButtonState enum's 0/1 cases.
    static func homeButton(pressed: Bool) -> RemoteXPCValue {
        .dictionary([
            "featureIdentifier": .string("com.apple.coredevice.feature.remote.hid.button"),
            "messageType": .string("IndigoButtonEvent"),
            "payload": .dictionary([
                "usagePage": .uint64(0x0c), "usageCode": .uint64(0x40),
                "state": .uint64(pressed ? 1 : 2)
            ])
        ])
    }

    static func touch(x: Double, y: Double, contact: Bool, timestamp: UInt64) throws -> Data {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw RorkDeviceError.invalidInput("Touch coordinates must be finite and inside the observed screen.")
        }
        let px = UInt16((x * 65535).rounded()), py = UInt16((y * 65535).rounded())
        var bytes = [UInt8](repeating: 0, count: 58)
        bytes[0...3] = [0x09, 0x01, 0x05, contact ? 0xc2 : 0x02]
        bytes[4] = UInt8(truncatingIfNeeded: px); bytes[5] = UInt8(px >> 8)
        bytes[6] = UInt8(truncatingIfNeeded: py); bytes[7] = UInt8(py >> 8)
        bytes[40] = 2
        for index in 0..<6 { bytes[44 + index] = UInt8(truncatingIfNeeded: timestamp >> (8 * index)) }
        return Data(bytes)
    }

    static func offer(sessionID: UInt32, callID: UUID = UUID()) throws -> Data {
        func tier(_ index: UInt64) -> Data { integer(1, 1) + integer(2, index) + integer(3, 50115) + integer(4, 0) }
        func bank(_ payload: UInt64, count: Int, kind: UInt64) -> Data {
            var data = integer(1, payload)
            for index in 0..<count { data += field(2, tier(UInt64(1 + index % 2))) }
            return data + field(3, Data("FLS;SW:1;".utf8)) + integer(4, kind)
        }
        let video = integer(1, UInt64(sessionID)) + integer(2, 0)
            + field(3, bank(123, count: 4, kind: 1)) + field(3, bank(100, count: 2, kind: 14))
            + integer(7, 0) + integer(8, 63) + integer(10, 1) + integer(12, 1)
        var blob = integer(1, 1) + integer(2, 1) + field(5, video)
            + field(6, Data("Viceroy 1.7.0".utf8)) + integer(8, 0)
        let tiers: [(UInt64, UInt64, UInt64?)] = [
            (4074, 0, 16384), (0, 75000000, 524288), (0, 40000000, 12288),
            (16, 4100, nil), (0, 20000000, 98304), (4, 6500, nil),
            (0, 6000000, 131072), (0, 100000000, 1048576), (0, 60000000, 262144), (1, 299, nil)
        ]
        for (kind, rate, buffer) in tiers {
            var value = integer(1, kind) + integer(2, rate)
            if let buffer { value += integer(3, buffer) }
            blob += field(9, value)
        }
        blob += integer(13, UInt64(Date().timeIntervalSince1970 * 1e9)) + integer(14, 2) + integer(16, 0) + integer(18, 1)
        // Describe this actual on-phone prototype, not a different trusted host.
        let endpoint = integer(1, 0) + integer(2, 1) + field(3, Data("iPhone18,4".utf8))
            + field(4, Data("27.2".utf8)) + field(5, Data("24B5089g".utf8))
        return try PropertyListSerialization.data(fromPropertyList: [
            "avcMediaStreamOptionRemoteEndpointInfo": endpoint,
            "avcMediaStreamNegotiatorMode": 5,
            "avcMediaStreamNegotiatorMediaBlob": storedZlib(blob),
            "avcMediaStreamOptionCallID": callID.uuidString
        ], format: .binary, options: 0)
    }

    private static func integer(_ number: UInt64, _ value: UInt64) -> Data { varint(number << 3) + varint(value) }
    private static func field(_ number: UInt64, _ value: Data) -> Data { varint(number << 3 | 2) + varint(UInt64(value.count)) + value }
    private static func varint(_ number: UInt64) -> Data {
        var value = number, bytes = Data()
        repeat {
            let low = UInt8(value & 127); value >>= 7
            bytes.append(low | (value == 0 ? 0 : 128))
        } while value != 0
        return bytes
    }

    /// RFC 1950/1951 stored blocks: interoperable zlib, without an extra codec.
    static func storedZlib(_ data: Data) -> Data {
        var result = Data([0x78, 0x01]), offset = 0
        repeat {
            let length = min(65535, data.count - offset)
            result.append(offset + length == data.count ? 1 : 0)
            let n = UInt16(length), complement = ~n
            result.append(contentsOf: [UInt8(truncatingIfNeeded: n), UInt8(n >> 8), UInt8(truncatingIfNeeded: complement), UInt8(complement >> 8)])
            result += data.subdata(in: offset..<(offset + length)); offset += length
        } while offset < data.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let sum = b << 16 | a
        result.append(contentsOf: [UInt8(sum >> 24), UInt8(truncatingIfNeeded: sum >> 16), UInt8(truncatingIfNeeded: sum >> 8), UInt8(truncatingIfNeeded: sum)])
        return result
    }
}

/// Receives and immediately discards this session's video datagrams. No frame
/// data is retained, recorded or transmitted outside the authenticated tunnel.
public final class PocketNativeMediaSink: @unchecked Sendable {
    public let port: UInt16
    private let lock = NSLock()
    private var count = 0
    public init(port: UInt16 = 47000) { self.port = port }
    public var packetsReceived: Int { lock.withLock { count } }
    func consume(_ packet: Data) -> Bool {
        let bytes = [UInt8](packet)
        guard bytes.count >= 48, bytes[0] >> 4 == 6, bytes[6] == 17,
              Int(bytes[4]) << 8 | Int(bytes[5]) == bytes.count - 40,
              UInt16(bytes[42]) << 8 | UInt16(bytes[43]) == port,
              Int(bytes[44]) << 8 | Int(bytes[45]) == bytes.count - 40 else { return false }
        lock.withLock { count += 1 }
        return true
    }
}
