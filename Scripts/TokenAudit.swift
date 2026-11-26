import Foundation

// Offline audit: real request encoding and tool schemas, scripted model decisions,
// synthetic screens. This executable never calls a provider or a physical device.
@main
struct TokenAudit {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        let app = try String(contentsOf: root.appendingPathComponent("PocketAgent/App/AppModel.swift"), encoding: .utf8)
        func context(_ prefix: String) throws -> String {
            let pattern = "\\\"(" + NSRegularExpression.escapedPattern(for: prefix) + "[^\\\"\\n]+)\\\""
            let regex = try NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: app, range: NSRange(app.startIndex..., in: app)),
                  let range = Range(match.range(at: 1), in: app) else { throw AuditError.missingContext }
            return String(app[range])
                .replacingOccurrences(of: #"\(screen.targetBundleID)"#, with: "com.apple.Preferences")
                .replacingOccurrences(of: #"\(screen.interactionMode.rawValue)"#, with: ScreenInteractionMode.act.rawValue)
        }
        let configuration = HomeNavigationTool.configurationContext(enabled: true, standingAccess: true)
            + " " + (try context("Native screen control is ENABLED"))
            + " " + (try context("Tapp cursor is enabled."))
        let scenarios: [(String, String, [Step])] = [
            ("basic_home", "Go Home", [.tool("phone_navigate", ["action": .string("go_home")]), .answer("Navigation dispatched. Check the phone.")]),
            ("basic_tap", "tap General", [.read, .tap("General"), .answer("One tap sent at General. Check the resulting capture.")]),
            ("basic_scroll", "scroll down", [.read, .tool("screen_swipe", ["direction": .string("up")]), .answer("One swipe sent. Check the resulting capture.")]),
            ("basic_model_navigation", "Return to the iPhone's Home Screen", [.tool("phone_navigate", ["action": .string("go_home")]), .answer("Navigation dispatched. Check the phone.")]),
            ("medium_highlight", "Show me where General is", [.read, .tool("screen_point", ["label": .string("General"), "element_type": .string("StaticText")]), .answer("Moved Tapp to General. Nothing was tapped.")]),
            ("intermediate_settings", "Open General, then About and tell me the iOS version", [.read, .tap("General"), .tap("About"), .answer("The synthetic About screen reports iOS 27.0.")])
        ]
        var reports: [[String: JSONValue]] = []
        for (name, prompt, steps) in scenarios {
            for optimized in [false, true] {
                let transport = AuditTransport(steps: steps, responses: optimized)
                let controller = AuditDevice()
                let model: any AgentModelClient = optimized
                    ? ResponsesModelClient(baseURL: "https://audit.invalid/v1", model: "gpt-6.1-sol", accessCode: "tapp_" + String(repeating: "x", count: 43), transport: transport)
                    : OpenAICompatibleClient(baseURL: "http://localhost/v1", model: "gpt-6.1-sol", transport: transport)
                let tools: [any AgentTool] = [CurrentTimeTool(), CreateReminderTool(),
                    HomeNavigationTool(device: controller, requiresApproval: false),
                    AppSwitcherTool(device: controller, requiresApproval: false)] +
                    [ScreenAction.read, .point, .tap, .hold, .drag, .swipe].map {
                        ScreenTool(action: $0, controller: controller, usesNativeOCR: true, approvalPolicy: .requestedActions)
                    }
                let wrapped = tools.map { AuditTool(tool: $0, optimized: optimized) }
                let session = AgentSession(model: model, tools: wrapped, scopeToolsToRequest: optimized)
                if let action = HomeNavigationAction.directCommand(prompt) {
                    // This shortcut already existed before the optimization.
                    _ = try await HomeNavigationTool(device: controller, requiresApproval: false)
                        .execute(arguments: ["action": .string(action.rawValue)])
                } else if optimized, let command = LocalScreenCommand.parse(prompt) {
                    _ = try await command.execute(bundleID: "com.apple.Preferences", controller: controller)
                } else {
                    let hint = IPhoneNavigationLanguage.intent(prompt).map(IPhoneNavigationLanguage.modelHint(for:)) ?? ""
                    _ = try await session.send(prompt + "\n\n[App configuration: \(configuration) \(hint)]")
                }
                let actions = await controller.actions
                let expected: [String]
                switch name {
                case "basic_home", "basic_model_navigation": expected = ["go_home"]
                case "basic_tap": expected = ["screen_read", "screen_tap"]
                case "basic_scroll": expected = ["screen_read", "screen_swipe"]
                case "medium_highlight": expected = ["screen_read", "screen_point"]
                default: expected = ["screen_read", "screen_tap", "screen_tap"]
                }
                guard actions == expected else { throw AuditError.unexpectedActions(name, actions) }
                reports.append(["scenario": .string(name), "request": .string(prompt),
                    "version": .string(optimized ? "optimized" : "baseline"),
                    "fixture_actions": .array(actions.map(JSONValue.string)),
                    "fixture_actions_verified": .bool(true),
                    "calls": .array(await transport.calls.map(JSONValue.object))])
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(reports).write(to: destination)
    }
}

private enum AuditError: Error { case missingContext, exhaustedScript, unexpectedActions(String, [String]) }
private enum Step: Sendable {
    case tool(String, [String: JSONValue]), answer(String)
    static var read: Self { .tool("screen_read", ["bundle_id": .string("com.apple.Preferences")]) }
    static func tap(_ label: String) -> Self { .tool("screen_tap", ["label": .string(label), "element_type": .string("StaticText")]) }
}

private actor AuditTransport: ModelHTTPTransport {
    var steps: [Step]
    var calls: [[String: JSONValue]] = []
    let responses: Bool
    init(steps: [Step], responses: Bool) { self.steps = steps; self.responses = responses }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        guard !steps.isEmpty, let body = request.httpBody, let url = request.url else { throw AuditError.exhaustedScript }
        let payload = try JSONDecoder().decode([String: JSONValue].self, from: body)
        let step = steps.removeFirst()
        let message: [String: JSONValue]
        switch step {
        case .answer(let content): message = ["content": .string(content)]
        case .tool(let name, var args):
            if name.hasPrefix("screen_") {
                args["bundle_id"] = .string("com.apple.Preferences")
                if name != "screen_read", case .array(let messages) = payload[responses ? "input" : "messages"],
                   case .object(let last) = messages.last, let text = last[responses ? "output" : "content"]?.stringValue {
                    let result = try JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8))
                    args["observation_id"] = result["observation_id"]
                }
            }
            let arguments = String(decoding: try JSONEncoder().encode(args), as: UTF8.self)
            message = ["content": .null, "tool_calls": .array([.object([
                "id": .string("audit-\(calls.count + 1)"), "type": .string("function"),
                "function": .object(["name": .string(name), "arguments": .string(arguments)])])])]
        }
        let response: [String: JSONValue]
        if responses {
            let output: [JSONValue]
            if case .array(let calls) = message["tool_calls"], case .object(let call) = calls.first,
               case .object(let function) = call["function"] {
                output = [.object(["type": .string("function_call"), "call_id": call["id"] ?? .null,
                    "name": function["name"] ?? .null, "arguments": function["arguments"] ?? .null])]
            } else {
                output = [.object(["type": .string("message"), "role": .string("assistant"),
                    "content": .array([.object(["type": .string("output_text"), "text": message["content"] ?? .string("")])])])]
            }
            response = ["status": .string("completed"), "output": .array(output)]
        } else { response = ["choices": .array([.object(["message": .object(message)])])] }
        calls.append(["request": .object(payload), "scripted_response": .object(message)])
        let data = try JSONEncoder().encode(response)
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private struct AuditTool: AgentTool {
    let tool: any AgentTool
    let optimized: Bool
    var definition: ToolDefinition { tool.definition }
    var requiresApproval: Bool { false }
    var returnsResultDirectly: Bool { optimized && tool.returnsResultDirectly }
    func approvalSummary(arguments: [String: JSONValue]) -> PendingApproval { tool.approvalSummary(arguments: arguments) }
    func execute(arguments: [String: JSONValue]) async throws -> String { try await tool.execute(arguments: arguments) }
}

private actor AuditDevice: ScreenActionController, HomeNavigationDevice, AppSwitcherDevice {
    private(set) var actions: [String] = []
    private var observation = 0
    private var labels = ["Settings", "General", "Accessibility", "Display & Brightness", "Battery", "Apps"]
    func configure(enabled: Bool, allowedBundleID: String, mode: ScreenInteractionMode) {}
    func disable() {}
    func cancel(operationID: UUID) {}
    func navigate(_ action: HomeNavigationAction, operationID: UUID) -> String {
        actions.append(action.rawValue)
        return "Return to Home: native operation dispatched; local result captured. Visually verify the destination."
    }
    func controlSwitcher(_ request: AppSwitcherRequest, operationID: UUID) -> String { "Synthetic App Switcher dispatch." }
    func perform(_ action: ScreenAction, arguments: [String: JSONValue], includeScreenshot: Bool) -> ScreenResult {
        actions.append(action.rawValue)
        observation += 1
        if action == .tap, arguments["label"] == .string("General") { labels = ["General", "About", "Software Update", "iPhone Storage"] }
        if action == .tap, arguments["label"] == .string("About") { labels = ["About", "Name", "Test iPhone", "iOS Version", "27.0"] }
        let frame = NativeScreenFrame(image: Data(), items: labels.enumerated().map { index, label in
            .init(label: label, x: 0.1, y: 0.15 + Double(index) * 0.1, width: 0.4, height: 0.04)
        })
        return ScreenResult(observationID: "fixture-\(observation)", bundleID: "com.apple.Preferences", text: frame.text,
            screenshot: nil, outcome: "Synthetic \(action.rawValue) completed. No physical device was used.", returnWarning: nil)
    }
}
