import Foundation
import XCTest
@testable import RorkDevice

final class PocketPointerProbeTests: XCTestCase {
    private let identity: UInt64 = 0x100001234

    func testMotionReportHasNoButtonBits() throws {
        for dx in -20...20 {
            for dy in -20...20 {
                let report = try PocketPointerProbe.motion(dx: dx, dy: dy)
                XCTAssertEqual(report.count, 17)
                XCTAssertEqual(report[0], 5)
                XCTAssertEqual(Int8(bitPattern: report[1]), Int8(dx))
                XCTAssertEqual(Int8(bitPattern: report[2]), Int8(dy))
                XCTAssertTrue(report[3..<17].allSatisfy { $0 == 0 })
                XCTAssertEqual(report[11], 0, "Apple's actual button mask offset")
                XCTAssertEqual(report[12], 0, "Apple's actual modifier mask offset")
            }
        }
    }

    func testLargeMotionsAreRejectedNotClamped() {
        for value in [Int.min, -21, 21, Int.max] {
            XCTAssertThrowsError(try PocketPointerProbe.motion(dx: value, dy: 0))
            XCTAssertThrowsError(try PocketPointerProbe.motion(dx: 0, dy: value))
        }
    }

    func testSpeedPresetsRampAndStayMotionOnly() throws {
        for speed in PocketPointerSpeed.allCases {
            for tick in 0..<2_250 {
                let step = speed.sweep(at: Double(tick) / 50)
                XCTAssertLessThanOrEqual(abs(step.dx), speed.maximumStep)
                XCTAssertLessThanOrEqual(abs(step.dy), speed.maximumStep)
                let report = try PocketPointerProbe.motion(dx: step.dx, dy: step.dy)
                XCTAssertTrue(report[3..<17].allSatisfy { $0 == 0 })
            }
            XCTAssertLessThan(speed.sweep(at: 0).dx, speed.sweep(at: 0.5).dx)
            XCTAssertEqual(speed.sweep(at: 0.5).dx, speed.maximumStep)
            XCTAssertEqual(speed.sweep(at: 2.5).dx, -speed.maximumStep)
        }
        XCTAssertEqual(PocketPointerSpeed.fast.maximumStep * 50, 500)
        XCTAssertEqual(PocketPointerSpeed.turbo.maximumStep * 50, 1_000)
    }

    func testSteeringSlowsNearTargetAndRejectsNonFiniteCoordinates() {
        for speed in PocketPointerSpeed.allCases {
            XCTAssertEqual(speed.toward(dxPoints: 5, dyPoints: -5), .zero)
            XCTAssertEqual(speed.toward(dxPoints: .nan, dyPoints: 2), .zero)
            XCTAssertEqual(speed.sweep(at: .infinity), .zero)
            XCTAssertEqual(speed.sweep(at: -1), .zero)
            XCTAssertEqual(speed.toward(dxPoints: 1_000, dyPoints: -1_000), .init(dx: speed.maximumStep, dy: -speed.maximumStep))
            XCTAssertEqual(speed.toward(dxPoints: Double.greatestFiniteMagnitude, dyPoints: 0).dx, speed.maximumStep)
            XCTAssertEqual(speed.toward(dxPoints: 8, dyPoints: -8), .init(dx: 1, dy: -1))
        }
    }

    func testDurationChoicesLeaveRoomForCountdownAndCleanup() {
        XCTAssertEqual(PocketPointerDuration.standard.rawValue, 30)
        for duration in PocketPointerDuration.allCases {
            XCTAssertTrue((10...45).contains(duration.rawValue))
            XCTAssertLessThan(duration.rawValue + 8 + 20, 90)
        }
    }

    func testDescriptorDefinesOnlyRelativeMotion() {
        // Parse short HID items; don't mistake arbitrary byte values for tags.
        let bytes = Array(PocketPointerProbe.descriptor)
        var offset = 0, page = 0, bits = 0, count = 0
        var totalBits = 0, axes: [Int] = []
        while offset < bytes.count {
            let prefix = bytes[offset]
            let size = [0, 1, 2, 4][Int(prefix & 3)]
            let data = Array(bytes[(offset + 1)..<(offset + 1 + size)])
            let value = data.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            switch prefix & 0xfc {
            case 0x04: page = value; XCTAssertEqual(page, 1, "No button or keyboard usage pages")
            case 0x08:
                if value >= 0x30 { axes.append(value) }
                XCTAssertTrue([1, 2, 0x30, 0x31].contains(value))
            case 0x74: bits = value
            case 0x94: count = value
            case 0x80:
                totalBits += bits * count
                XCTAssertTrue(value == 1 || value == 6, "Only constant padding or relative motion")
                XCTAssertEqual(page, 1)
            default: break
            }
            offset += size + 1
        }
        XCTAssertEqual(axes, [0x30, 0x31])
        XCTAssertEqual(totalBits, 128) // 16 payload bytes + report ID
    }

    func testWireMatchesNativePointerOffsetsNotGenericUSBLayout() throws {
        // Independent golden vectors from the shipped framework's field
        // getters, not a round-trip through our descriptor or encoder.
        XCTAssertEqual(try PocketPointerProbe.motion(dx: 3, dy: -4),
            Data([5, 3, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(try PocketPointerProbe.motion(dx: -3, dy: 4),
            Data([5, 253, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    }

    func testCreationTruthfullyNamesOwnDeviceAndUsesExactDescriptor() throws {
        let created = try XCTUnwrap(PocketPointerProbe.creation(serviceID: identity).dictionaryValue)
        try PocketPointerProbe.verifyCreated([created], serviceID: identity)
        XCTAssertEqual(created["Product"], .string("Pocket Agent Pointer Experiment"))
        let storage = try XCTUnwrap(created["_CoreDevice_codablePropertyStorage"]?.dictionaryValue)
        XCTAssertNil(storage["Authenticated"])
        XCTAssertNil(storage["Built-In"])
        XCTAssertNil(storage["_CoreDevice_suppressMousePointer"])
    }

    func testInventoryRequiresIdentifiedServicesAndKnownEnvelope() throws {
        let device = PocketPointerProbe.creation(serviceID: identity)
        XCTAssertEqual(try PocketPointerProbe.services(.dictionary(["connectedServices": .array([device])])).count, 1)
        for reply: RemoteXPCValue in [.null, .dictionary([:]), .dictionary(["connectedServices": .array([.dictionary([:])])])] {
            XCTAssertThrowsError(try PocketPointerProbe.services(reply))
        }
    }

    func testUnknownReusedOrMismatchedPointerCannotReceiveMotion() throws {
        let device = try XCTUnwrap(PocketPointerProbe.creation(serviceID: identity).dictionaryValue)
        XCTAssertThrowsError(try PocketPointerProbe.verifyCreated([], serviceID: identity))
        XCTAssertThrowsError(try PocketPointerProbe.verifyCreated([device, device], serviceID: identity))
        XCTAssertThrowsError(try PocketPointerProbe.verifyCreated([device], serviceID: identity + 1))
        for key in ["PrimaryUsage", "PrimaryUsagePage", "_CoreDevice_codablePropertyStorage"] {
            var invalid = device; invalid[key] = .null
            XCTAssertThrowsError(try PocketPointerProbe.verifyCreated([invalid], serviceID: identity))
        }
    }

    func testProjectedProductLabelsDoNotReplaceIDAndDescriptorChecks() throws {
        var device = try XCTUnwrap(PocketPointerProbe.creation(serviceID: identity).dictionaryValue)
        device["Product"] = .string("System-projected pointer label")
        try PocketPointerProbe.verifyCreated([device], serviceID: identity)
        var storage = try XCTUnwrap(device["_CoreDevice_codablePropertyStorage"]?.dictionaryValue)
        storage["Product"] = .dictionary(["string": .string("Another device")])
        device["_CoreDevice_codablePropertyStorage"] = .dictionary(storage)
        try PocketPointerProbe.verifyCreated([device], serviceID: identity)
        storage["Product"] = nil
        device["_CoreDevice_codablePropertyStorage"] = .dictionary(storage)
        try PocketPointerProbe.verifyCreated([device], serviceID: identity)
        storage["ReportDescriptor"] = .dictionary(["data": .data(Data([0]))])
        device["_CoreDevice_codablePropertyStorage"] = .dictionary(storage)
        XCTAssertThrowsError(try PocketPointerProbe.verifyCreated([device], serviceID: identity))
    }

    func testInventoryDiagnosticOmitsSensitivePropertyValues() {
        let diagnostic = PocketNativeEngine.pointerInventorySummary(.dictionary([
            "SerialNumber": .string("private-serial"), "PairingKey": .data(Data([1, 2, 3])),
            "Product": .string("Pocket Agent Pointer Experiment")
        ]))
        XCTAssertFalse(diagnostic.contains("private-serial"))
        XCTAssertTrue(diagnostic.contains("Pocket Agent Pointer Experiment"))
        XCTAssertTrue(diagnostic.contains("<3 bytes>"))
    }

    func testRegistrationFailureExplainsMismatchWithoutLoggingPropertyValues() throws {
        var device = try XCTUnwrap(PocketPointerProbe.creation(serviceID: identity).dictionaryValue)
        device["Product"] = .string("private-unexpected-value")
        device["_CoreDevice_codablePropertyStorage"] = .dictionary([:])
        XCTAssertThrowsError(try PocketPointerProbe.verifyCreated([device], serviceID: identity)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("No motion sent"))
            XCTAssertTrue(message.contains("product: false"))
            XCTAssertTrue(message.contains("descriptor: missing or unexpected encoding"))
            XCTAssertFalse(message.contains("private-unexpected-value"))
        }
    }
}
