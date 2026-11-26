import Foundation
import Testing
@testable import PocketAgentCore

@Suite("Supervised screen control")
struct ScreenControlTests {
    let target = "com.apple.Preferences"
    let caller = "com.example.PocketAgent"

    @Test("Disabled control sends no RPC")
    func disabled() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        await #expect(throws: ScreenControlError.disabled) {
            try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        }
        #expect(await rpc.methods.isEmpty)
    }

    @Test("Scope is enforced in code, not just in the prompt")
    func scope() async throws {
        let rpc = ScreenPeer(), controller = ScreenController(rpc: ScreenPeer(), returnBundleID: caller)
        let guarded = ScreenController(rpc: rpc, returnBundleID: caller)
        try await guarded.configure(enabled: true, allowedBundleID: target)
        await #expect(throws: ScreenControlError.wrongApp) {
            try await guarded.perform(.read, arguments: ["bundle_id": .string("com.apple.MobileSMS")])
        }
        #expect(await rpc.methods.isEmpty)
        await #expect(throws: ScreenControlError.invalidArguments) {
            try await controller.configure(enabled: true, allowedBundleID: "com.apple.springboard")
        }
    }

    @Test("Read activates target, captures locally and returns to caller")
    func read() async throws {
        let rpc = ScreenPeer(), controller = ScreenController(rpc: ScreenPeer(), returnBundleID: caller)
        let connected = ScreenController(rpc: rpc, returnBundleID: caller)
        try await connected.configure(enabled: true, allowedBundleID: target)
        let result = try await connected.perform(.read, arguments: ["bundle_id": .string(target)], includeScreenshot: true)
        #expect(result.text == "General button")
        #expect(result.screenshot == Data([1, 2, 3]))
        #expect(result.modelText.contains("untrusted_screen_text"))
        #expect(!result.modelText.contains("screenshot"))
        #expect(await rpc.methods == ["device_info", "activate_app", "page_source", "screenshot", "activate_app"])
        #expect(await rpc.lastActivated == caller)
        #expect(ScreenAction.allCases.allSatisfy { ScreenTool(action: $0, controller: controller).requiresApproval })
    }

    @Test("Tap re-finds an exact label and uses an element ref")
    func tap() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target, mode: .act)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        _ = try await controller.perform(.tap, arguments: ["bundle_id": .string(target), "observation_id": .string(read.observationID), "label": .string("General")])
        #expect(await rpc.tapArguments == ["ref": .string("el_1")])
        #expect(await rpc.findArguments?["match"] == .string("exact"))
        #expect(await rpc.lastActivated == caller)
    }

    @Test("Changed screens block gestures")
    func staleScreen() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target, mode: .act)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        await rpc.changeTree()
        await #expect(throws: ScreenControlError.staleScreen) {
            try await controller.perform(.tap, arguments: ["bundle_id": .string(target), "observation_id": .string(read.observationID), "label": .string("General")])
        }
        #expect(await rpc.tapArguments == nil)
        #expect(await rpc.lastActivated == caller)
    }

    @Test("Extra parameters, invalid swipes and newline submits are rejected before network access")
    func invalidArgs() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target, mode: .act)
        await #expect(throws: ScreenControlError.invalidArguments) {
            try await controller.perform(.type, arguments: ["bundle_id": .string(target), "observation_id": .string("x"), "label": .string("Search"), "text": .string("send this\n")])
        }
        await #expect(throws: ScreenControlError.invalidArguments) {
            try await controller.perform(.read, arguments: ["bundle_id": .string(target), "allow_remote_access": .bool(true)])
        }
        await #expect(throws: ScreenControlError.invalidArguments) {
            try await controller.perform(.swipe, arguments: ["bundle_id": .string(target), "observation_id": .string("x"), "direction": .string("diagonal")])
        }
        #expect(await rpc.methods.isEmpty)
    }

    @Test("Ambiguous controls are not tapped")
    func ambiguity() async throws {
        let rpc = ScreenPeer(ambiguous: true)
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target, mode: .act)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        await #expect(throws: ScreenControlError.ambiguousElement) {
            try await controller.perform(.tap, arguments: ["bundle_id": .string(target), "observation_id": .string(read.observationID), "label": .string("General")])
        }
        #expect(await rpc.tapArguments == nil)
    }

    @Test("System alerts and failed foreground switches block access")
    func alerts() async throws {
        for mode in [ScreenPeer.Activation.alert, .wrongApp] {
            let rpc = ScreenPeer(activation: mode)
            let controller = ScreenController(rpc: rpc, returnBundleID: caller)
            try await controller.configure(enabled: true, allowedBundleID: target)
            await #expect(throws: mode == .alert ? ScreenControlError.blockedByAlert : .wrongApp) {
                try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
            }
            #expect(await rpc.methods.contains("page_source") == false)
        }
    }

    @Test("Typing appends without clearing or submitting")
    func typing() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target, mode: .act)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        _ = try await controller.perform(.type, arguments: ["bundle_id": .string(target), "observation_id": .string(read.observationID), "label": .string("Search"), "text": .string("hello")])
        #expect(await rpc.typeArguments == ["text": .string("hello"), "submit": .bool(false), "clear": .bool(false)])
    }

    @Test("Swipes use a bounded slow gesture and require a fresh read")
    func swipe() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target, mode: .act)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        _ = try await controller.perform(.swipe, arguments: ["bundle_id": .string(target), "observation_id": .string(read.observationID), "direction": .string("up")])
        #expect(await rpc.swipeArguments == ["direction": .string("up"), "distance": .number(180), "velocity": .string("slow")])
    }

    @Test("Stop during an in-flight read prevents all subsequent operations")
    func stopInFlight() async throws {
        let rpc = PausingScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target)
        let work = Task { try await controller.perform(.read, arguments: ["bundle_id": .string(target)]) }
        await rpc.waitUntilStarted()
        await controller.disable()
        await rpc.resume()
        await #expect(throws: ScreenControlError.disabled) { try await work.value }
        #expect(await rpc.methods == ["device_info"])
    }

    @Test("Screen actions go through the actual agent approval boundary")
    func agentApproval() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target)
        let model = ScreenRequestModel(bundle: target)
        let session = AgentSession(model: model, tools: [ScreenTool(action: .read, controller: controller)])
        let event = try await session.send("Inspect Settings")
        guard case .approvalRequired(let approval) = event else { Issue.record("Expected approval"); return }
        #expect(approval.explanation.contains("configured model"))
        #expect(await rpc.methods.isEmpty)
        _ = try await session.approvePendingAction()
        #expect(await rpc.methods.contains("page_source"))
    }

    @Test("Guide mode blocks every write before contacting the runner")
    func guideMode() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target)
        for action in [ScreenAction.tap, .type, .swipe] {
            await #expect(throws: ScreenControlError.guideOnly) {
                try await controller.perform(action, arguments: ["bundle_id": .string(target)])
            }
        }
        #expect(await rpc.methods.isEmpty)
    }

    @Test("Pointing resolves observed bounds and never taps or types")
    func point() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        let point = try await controller.perform(.point, arguments: ["bundle_id": .string(target),
            "observation_id": .string(read.observationID), "label": .string("General")])
        #expect(point.highlight?.label == "General")
        #expect(point.highlight?.x == 0.05)
        #expect(point.highlight?.y == 0.25)
        #expect(point.highlight?.width == 0.9)
        #expect(point.highlight?.height == 0.0625)
        #expect(point.screenshot != nil)
        #expect(point.modelText.contains("Nothing was tapped"))
        #expect(await rpc.tapArguments == nil)
        #expect(await rpc.typeArguments == nil)
        #expect(await rpc.lastActivated == caller)
    }

    @Test("Invalid, off-screen, nonfinite and missing bounds cannot become a highlight")
    func invalidHighlight() throws {
        let shot: [String: JSONValue] = ["point_width": .number(400), "point_height": .number(800)]
        let good: [String: JSONValue] = ["x": .number(20), "y": .number(200), "width": .number(360), "height": .number(50)]
        for (key, value) in [("x", -1.0), ("y", 800.0), ("width", 0.0), ("height", Double.infinity)] {
            var bad = good
            bad[key] = .number(value)
            #expect(throws: ScreenControlError.ambiguousElement) { try ScreenHighlight(label: "General", element: bad, screenshot: shot) }
        }
        #expect(throws: ScreenControlError.ambiguousElement) { try ScreenHighlight(label: "General", element: good, screenshot: [:]) }
    }

    @Test("Ambiguous guidance is rejected without a gesture")
    func ambiguousPoint() async throws {
        let rpc = ScreenPeer(ambiguous: true)
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        await #expect(throws: ScreenControlError.ambiguousElement) {
            try await controller.perform(.point, arguments: ["bundle_id": .string(target),
                "observation_id": .string(read.observationID), "label": .string("General")])
        }
        #expect(await rpc.tapArguments == nil)
    }

    @Test("A changing screen cannot receive a misleading highlight")
    func pointDuringScreenChange() async throws {
        let rpc = ScreenPeer(screenshotChangesTree: true)
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        await #expect(throws: ScreenControlError.staleScreen) {
            try await controller.perform(.point, arguments: ["bundle_id": .string(target),
                "observation_id": .string(read.observationID), "label": .string("General")])
        }
        #expect(await rpc.tapArguments == nil)
    }

    @Test("Observed control type narrows the exact-label query without weakening ambiguity checks")
    func typedTarget() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        try await controller.configure(enabled: true, allowedBundleID: target)
        let read = try await controller.perform(.read, arguments: ["bundle_id": .string(target)])
        _ = try await controller.perform(.point, arguments: ["bundle_id": .string(target),
            "observation_id": .string(read.observationID), "label": .string("General"), "element_type": .string("Cell")])
        #expect(await rpc.findArguments?["element_type"] == .string("Cell"))
        #expect(await rpc.findArguments?["match"] == .string("exact"))
        let calls = await rpc.methods.count
        await #expect(throws: ScreenControlError.invalidArguments) {
            try await controller.perform(.point, arguments: ["bundle_id": .string(target),
                "observation_id": .string(read.observationID), "label": .string("General"), "element_type": .string("any predicate")])
        }
        #expect(await rpc.methods.count == calls)
    }

    @Test("Only target type is optional in point/tap model schemas")
    func toolSchemas() throws {
        let controller = ScreenController(rpc: ScreenPeer(), returnBundleID: caller)
        for action in ScreenAction.allCases {
            let definition = ScreenTool(action: action, controller: controller).definition
            guard case .array(let required) = definition.parameters["required"] else { Issue.record("Missing schema"); return }
            #expect(required.contains(.string("bundle_id")))
            #expect(!required.contains(.string("element_type")))
            #expect(required.contains(.string("label")) == [.point, .tap, .type, .hold, .drag].contains(action))
            #expect(required.contains(.string("destination_label")) == (action == .drag))
            #expect(required.contains(.string("text")) == (action == .type))
            #expect(required.contains(.string("direction")) == (action == .swipe))
        }
    }

    @Test("Agent screen results publish a local preview but never send image bytes to the model")
    func previewDelivery() async throws {
        let rpc = ScreenPeer()
        let controller = ScreenController(rpc: rpc, returnBundleID: caller)
        let sink = PreviewSink()
        try await controller.configure(enabled: true, allowedBundleID: target)
        let tool = ScreenTool(action: .read, controller: controller, onResult: { await sink.receive($0) })
        let text = try await tool.execute(arguments: ["bundle_id": .string(target)])
        #expect(await sink.events == ["clear", "preview"])
        #expect(await sink.result?.screenshot == Data([1, 2, 3]))
        #expect(!text.contains(Data([1, 2, 3]).base64EncodedString()))
        await controller.disable()
        await #expect(throws: ScreenControlError.disabled) {
            try await tool.execute(arguments: ["bundle_id": .string(target)])
        }
        #expect(await sink.events == ["clear", "preview", "clear"])
        #expect(await sink.result == nil)
    }
}

private actor PreviewSink {
    private(set) var events: [String] = []
    private(set) var result: ScreenResult?
    func receive(_ value: ScreenResult?) {
        result = value
        events.append(value == nil ? "clear" : "preview")
    }
}

private actor ScreenPeer: ScreenRPC {
    enum Activation { case normal, alert, wrongApp }
    let ambiguous: Bool
    let activation: Activation
    let screenshotChangesTree: Bool
    var tree = "General button"
    private(set) var methods: [String] = []
    private(set) var lastActivated = ""
    private(set) var tapArguments: [String: JSONValue]?
    private(set) var findArguments: [String: JSONValue]?
    private(set) var typeArguments: [String: JSONValue]?
    private(set) var swipeArguments: [String: JSONValue]?
    init(ambiguous: Bool = false, activation: Activation = .normal, screenshotChangesTree: Bool = false) {
        self.ambiguous = ambiguous; self.activation = activation
        self.screenshotChangesTree = screenshotChangesTree
    }
    func changeTree() { tree = "An unrelated screen" }
    func call(_ method: String, parameters: [String: JSONValue]) async throws -> [String: JSONValue] {
        methods.append(method)
        switch method {
        case "device_info": return ["protocol_version": .number(1)]
        case "activate_app":
            lastActivated = parameters["bundle_id"]?.stringValue ?? ""
            return ["foreground_app": .string(activation == .wrongApp ? "com.apple.Other" : lastActivated), "system_alert": .bool(activation == .alert)]
        case "page_source": return ["source": .string(tree)]
        case "screenshot":
            if screenshotChangesTree { tree = "Screen changed while capturing" }
            return ["data": .string(Data([1, 2, 3]).base64EncodedString()), "point_width": .number(400), "point_height": .number(800)]
        case "find_element":
            findArguments = parameters
            return ["exists": .bool(true), "hittable": .bool(true), "ref": .string("el_1"), "match_count": .number(ambiguous ? 2 : 1),
                    "visibility": .string("in_view"), "is_text_input": .bool(true),
                    "x": .number(20), "y": .number(200), "width": .number(360), "height": .number(50)]
        case "tap": tapArguments = parameters; return ["message": .string("Tapped")]
        case "type": typeArguments = parameters; return ["message": .string("Typed")]
        case "swipe": swipeArguments = parameters; return ["message": .string("Swiped")]
        default: throw ICTRLError.rpc(-32601, "Unsupported test method")
        }
    }
}

private actor PausingScreenPeer: ScreenRPC {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private(set) var methods: [String] = []
    func call(_ method: String, parameters: [String: JSONValue]) async throws -> [String: JSONValue] {
        methods.append(method)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer?.resume()
            observer = nil
        }
        return ["protocol_version": .number(1)]
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

private actor ScreenRequestModel: AgentModelClient {
    let bundle: String
    init(bundle: String) { self.bundle = bundle }
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async throws -> ModelReply {
        if messages.last?.role == .tool { return ModelReply(content: "Read complete") }
        return ModelReply(toolCalls: [ToolCall(id: "screen-1", name: "screen_read", arguments: ["bundle_id": .string(bundle)])])
    }
}
