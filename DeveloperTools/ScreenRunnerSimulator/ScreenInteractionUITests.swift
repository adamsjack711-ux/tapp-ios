import XCTest
import PocketAgentCore

/// Real simulator UI, with the pinned iCTRL action dispatcher as the RPC transport.
/// This checks screen interaction, not encrypted pairing or physical-device compatibility.
final class ScreenInteractionUITests: XCTestCase {
    @MainActor
    func testReadPointAndApprovedTap() async throws {
        continueAfterFailure = false
        EarlyURLHook.markSetUpEntered()
        let target = "com.apple.Preferences"
        let caller = "com.jackadamslovell.PocketAgent"
        let settings = XCUIApplication(bundleIdentifier: target)
        settings.terminate()
        settings.launch()
        let pocket = XCUIApplication(bundleIdentifier: caller)
        pocket.launch()
        let rpc = RealScreenRPC()
        let controller = PocketAgentCore.ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target, mode: .guide)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)], includeScreenshot: true)
        XCTAssertTrue(read.text.contains("General"))
        print("SIMULATOR TEST observed General: \(read.text.split(separator: "\n").filter { $0.contains("General") })")
        XCTAssertTrue(read.text.split(separator: "\n").contains { $0.contains("General") && $0.contains("Button") }, "Button must be observed, not guessed")
        let point = try await controller.perform(.point, arguments: ["bundle_id": .string(target),
            "observation_id": .string(read.observationID), "label": .string("General"), "element_type": .string("Button")])
        XCTAssertEqual(point.highlight?.label, "General")
        XCTAssertNotNil(point.screenshot)
        XCTAssertFalse(rpc.methods.contains("tap"))
        XCTAssertTrue(pocket.wait(for: .runningForeground, timeout: 5))
        let fixture = XCTAttachment(data: try JSONEncoder().encode(point), uniformTypeIdentifier: "public.json")
        fixture.name = "GuidanceCapture.json"
        fixture.lifetime = .keepAlways
        add(fixture)
        if let data = point.screenshot, let image = UIImage(data: data) {
            let capture = XCTAttachment(image: image)
            capture.name = "Real Settings screen before approved tap"
            capture.lifetime = .keepAlways
            add(capture)
        }
        do {
            _ = try await controller.perform(.tap, arguments: ["bundle_id": .string(target),
                "observation_id": .string(point.observationID), "label": .string("General")])
            XCTFail("Guide mode must not tap")
        } catch PocketAgentCore.ScreenControlError.guideOnly {}
        XCTAssertFalse(rpc.methods.contains("tap"))

        // Explicitly switch modes, then obtain a fresh observation.
        try await controller.configure(enabled: true, allowedBundleID: target, mode: .act)
        let ready = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        let result = try await controller.perform(.tap, arguments: ["bundle_id": .string(target),
            "observation_id": .string(ready.observationID), "label": .string("General"), "element_type": .string("Button")], includeScreenshot: true)
        XCTAssertTrue(rpc.methods.contains("tap"))
        XCTAssertTrue(result.text.contains("About"), "Expected General's About row in the resulting UI")
        XCTAssertTrue(pocket.wait(for: .runningForeground, timeout: 5))
        await controller.disable()
    }
}

@MainActor
private final class RealScreenRPC: PocketAgentCore.ScreenRPC {
    private let handler = ActionHandler(app: XCUIApplication(bundleIdentifier: "com.apple.springboard"))
    private(set) var methods: [String] = []

    func call(_ method: String, parameters: [String: PocketAgentCore.JSONValue]) async throws -> [String: PocketAgentCore.JSONValue] {
        methods.append(method)
        // Convert between the two independently defined JSON value types at the wire boundary.
        let params = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(parameters))
        let (response, error) = handler.dispatch(method: method, params: params)
        if let error { throw PocketAgentCore.ICTRLError.rpc(error.code, error.message) }
        guard let response else { throw PocketAgentCore.ICTRLError.invalidResponse }
        if method == "find_element" || method == "screenshot" {
            let keys: Set<String> = ["exists", "hittable", "ref", "match_count", "visibility", "x", "y", "width", "height", "point_width", "point_height"]
            print("SIMULATOR TEST \(method): \(response.filter { keys.contains($0.key) })")
        }
        return try JSONDecoder().decode([String: PocketAgentCore.JSONValue].self, from: JSONEncoder().encode(response))
    }
}
