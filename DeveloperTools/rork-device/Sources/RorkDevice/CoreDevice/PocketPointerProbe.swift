import Foundation

public enum PocketPointerSpeed: String, CaseIterable, Sendable {
    case precise = "Precise", fast = "Fast", turbo = "Turbo"

    public var maximumStep: Int {
        switch self { case .precise: 3; case .fast: 10; case .turbo: 20 }
    }

    /// Software velocity ramp, not an unverified native acceleration flag.
    /// 50 Hz versus the original 13 Hz; no phone tracking preference changes.
    public func sweep(at elapsed: Double) -> PocketPointerMotion {
        guard elapsed.isFinite, elapsed >= 0 else { return .zero }
        let phase = elapsed.truncatingRemainder(dividingBy: 4)
        let leg = Int(phase)
        let fraction = phase - Double(leg)
        let ramp = min(1, min(fraction, 1 - fraction) / 0.2)
        let step = max(1, Int((Double(maximumStep) * ramp).rounded()))
        switch leg {
        case 0: return .init(dx: step, dy: 0)
        case 1: return .init(dx: 0, dy: step)
        case 2: return .init(dx: -step, dy: 0)
        default: return .init(dx: 0, dy: -step)
        }
    }

    /// Relative units are not pixels. Fresh observed hover feedback is needed
    /// on every step; slow near the target rather than integrating sent deltas.
    public func toward(dxPoints: Double, dyPoints: Double) -> PocketPointerMotion {
        guard dxPoints.isFinite, dyPoints.isFinite else { return .zero }
        func axis(_ delta: Double) -> Int {
            guard abs(delta) > 6 else { return 0 }
            return (delta < 0 ? -1 : 1) * min(maximumStep, max(1, Int(min(1_000, abs(delta)) * 0.12)))
        }
        return .init(dx: axis(dxPoints), dy: axis(dyPoints))
    }
}

public enum PocketPointerDuration: Int, CaseIterable, Sendable {
    case short = 10, standard = 30, extended = 45
}

public struct PocketPointerMotion: Sendable, Equatable {
    public let dx: Int
    public let dy: Int
    public init(dx: Int, dy: Int) { self.dx = dx; self.dy = dy }
    public static let zero = Self(dx: 0, dy: 0)
}

/// A diagnostic mouse, not a general-purpose input API. Its descriptor contains
/// no buttons, wheel, keyboard or absolute/touch usages. Motion is bounded and
/// cannot be promoted to agent control without physical verification.
enum PocketPointerProbe {
    static let product = "Pocket Agent Pointer Experiment"
    // CoreDevice decodes UniversalHID.PointerReport, not an arbitrary USB
    // report matching the advertised descriptor. Confirmed against the shipped
    // UniversalHID binary: initialReportBitCount = 136; signed X/Y at bits 8/16,
    // acceleration at 24/56, buttons at 88, modifiers at 96, flags at 104.
    // The former six-byte [id, padding, x16, y16] report was incompatible.
    // Use the 17-byte base report; its optional remote timestamp is omitted.
    static let reportByteCount = 17
    static let descriptor = Data([
        0x05, 0x01,             // Generic Desktop
        0x09, 0x02,             // Mouse
        0xa1, 0x01,             // Application collection
        0x85, 0x05,             // Report ID 5
        0x09, 0x01,             // Pointer
        0xa1, 0x00,             // Physical collection
        0x09, 0x30, 0x09, 0x31, // X, Y
        0x15, 0x80,             // Logical minimum -128
        0x25, 0x7f,             // Logical maximum 127
        0x75, 0x08, 0x95, 0x02, // Two 8-bit relative values, wire bytes 1/2
        0x81, 0x06,             // Data, variable, relative
        0x75, 0x08, 0x95, 0x0e, // 14 constant bytes; no buttons/modifiers
        0x81, 0x01,             // Acceleration, buttons, modifiers, flags = 0
        0xc0, 0xc0
    ])

    static func motion(dx: Int, dy: Int) throws -> Data {
        guard (-20...20).contains(dx), (-20...20).contains(dy) else {
            throw RorkDeviceError.invalidInput("Pointer experiment allows at most twenty relative units per sample.")
        }
        var report = Data(repeating: 0, count: reportByteCount)
        report[0] = 5
        report[1] = UInt8(bitPattern: Int8(dx))
        report[2] = UInt8(bitPattern: Int8(dy))
        return report
    }

    static func creation(serviceID: UInt64) -> RemoteXPCValue {
        let pair: RemoteXPCValue = .dictionary(["DeviceUsage": .int64(2), "DeviceUsagePage": .int64(1)])
        let storage: RemoteXPCValue = .dictionary([
            "Product": .dictionary(["string": .string(product)]),
            "Manufacturer": .dictionary(["string": .string("Pocket Agent")]),
            "PrimaryUsage": .dictionary(["int": .int64(2)]),
            "PrimaryUsagePage": .dictionary(["int": .int64(1)]),
            "DeviceUsagePairs": .dictionary(["array": .array([
                .dictionary(["dictionary": .dictionary([
                    "DeviceUsage": .dictionary(["int": .int64(2)]),
                    "DeviceUsagePage": .dictionary(["int": .int64(1)])
                ])])
            ])]),
            "Transport": .dictionary(["string": .string("Virtual")]),
            "ReportDescriptor": .dictionary(["data": .data(descriptor)]),
            "UniversalControlVirtualService": .dictionary(["bool": .bool(true)]),
            "_ServiceID": .dictionary(["uint": .uint64(serviceID)])
        ])
        return .dictionary([
            "DeviceUsagePairs": .array([pair]), "PrimaryUsage": .uint64(2), "PrimaryUsagePage": .uint64(1),
            "Product": .string(product), "_ServiceID": .uint64(serviceID), "_CoreDevice_codablePropertyStorage": storage
        ])
    }

    static func services(_ reply: RemoteXPCValue) throws -> [[String: RemoteXPCValue]] {
        guard case .array(let values) = reply.dictionaryValue?["connectedServices"], values.count < 128 else {
            throw RorkDeviceError.protocolViolation("Cannot verify HID device inventory. No mouse movement allowed.")
        }
        return try values.map {
            guard let fields = $0.dictionaryValue, case .uint64 = fields["_ServiceID"] else {
                throw RorkDeviceError.protocolViolation("Unidentified HID device. No mouse movement allowed.")
            }
            return fields
        }
    }

    static func verifyCreated(_ services: [[String: RemoteXPCValue]], serviceID: UInt64) throws {
        let matches = services.filter { $0["_ServiceID"] == .uint64(serviceID) }
        guard matches.count == 1, let service = matches.first,
              // iOS rewrites both Product labels. Ownership is the randomly
              // chosen ID (absent before creation and echoed by createService),
              // and the exact no-button descriptor, not a cosmetic name.
              service["PrimaryUsage"] == .uint64(2),
              service["PrimaryUsagePage"] == .uint64(1),
              service["_CoreDevice_codablePropertyStorage"]?.dictionaryValue?["ReportDescriptor"]?.dictionaryValue?["data"] == .data(descriptor) else {
            // Only our requested identity is inspected. Keep values out of the
            // diagnostic; this identifies protocol mismatches without logging
            // other devices, credentials or descriptor bytes.
            let service = matches.first ?? [:]
            let storage = service["_CoreDevice_codablePropertyStorage"]?.dictionaryValue
            let returned = storage?["ReportDescriptor"]?.dictionaryValue?["data"]
            let descriptorState: String
            if case .data(let bytes) = returned {
                descriptorState = bytes == descriptor ? "exact" : "different (\(bytes.count) bytes)"
            } else { descriptorState = "missing or unexpected encoding" }
            throw RorkDeviceError.protocolViolation("The new mouse descriptor was not verified. No motion sent. Matches: \(matches.count); stored product: \(storage?["Product"]?.dictionaryValue?["string"] == .string(product)); usage: \(service["PrimaryUsage"] == .uint64(2)); page: \(service["PrimaryUsagePage"] == .uint64(1)); descriptor: \(descriptorState).")
        }
    }
}
