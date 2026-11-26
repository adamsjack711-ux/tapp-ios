import Foundation

public enum PocketPointerClickStep: Sendable {
    case move(PocketPointerMotion)
    case click
}

/// Separate from the existing movement-only probe. Exactly one primary button,
/// no keyboard, wheel, secondary buttons, absolute positioning or acceleration.
enum PocketPointerClick {
    static let descriptor = Data([
        0x05, 0x01, 0x09, 0x02, 0xa1, 0x01, 0x85, 0x05,
        0x09, 0x01, 0xa1, 0x00,
        0x09, 0x30, 0x09, 0x31, 0x15, 0x80, 0x25, 0x7f,
        0x75, 0x08, 0x95, 0x02, 0x81, 0x06, // X/Y at bytes 1/2
        0x75, 0x08, 0x95, 0x08, 0x81, 0x01, // acceleration padding, bytes 3...10
        0x05, 0x09, 0x09, 0x01, 0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95, 0x01, 0x81, 0x02, // primary button at byte 11, bit 0
        0x75, 0x01, 0x95, 0x07, 0x81, 0x01,
        0x75, 0x08, 0x95, 0x05, 0x81, 0x01, // modifiers/flags stay zero
        0xc0, 0xc0
    ])
    static func button(pressed: Bool) -> Data {
        var bytes = Data(repeating: 0, count: 17)
        bytes[0] = 5; bytes[11] = pressed ? 1 : 0
        return bytes
    }
    static func creation(serviceID: UInt64) -> RemoteXPCValue {
        var fields = PocketPointerProbe.creation(serviceID: serviceID).dictionaryValue!
        var storage = fields["_CoreDevice_codablePropertyStorage"]!.dictionaryValue!
        fields["Product"] = .string("Pocket Agent Single Click")
        storage["Product"] = .dictionary(["string": .string("Pocket Agent Single Click")])
        storage["ReportDescriptor"] = .dictionary(["data": .data(descriptor)])
        fields["_CoreDevice_codablePropertyStorage"] = .dictionary(storage)
        return .dictionary(fields)
    }
    static func verify(_ services: [[String: RemoteXPCValue]], id: UInt64) throws {
        let found = services.filter { $0["_ServiceID"] == .uint64(id) }
        guard found.count == 1, let service = found.first,
              service["PrimaryUsage"] == .uint64(2), service["PrimaryUsagePage"] == .uint64(1),
              service["_CoreDevice_codablePropertyStorage"]?.dictionaryValue?["ReportDescriptor"]?.dictionaryValue?["data"] == .data(descriptor) else {
            throw RorkDeviceError.protocolViolation("Single-click mouse identity/descriptor not verified. No input allowed.")
        }
    }
}
