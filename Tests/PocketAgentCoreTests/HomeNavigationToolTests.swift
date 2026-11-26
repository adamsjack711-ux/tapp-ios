import Foundation
import Testing
@testable import PocketAgentCore

@Suite("Approved Home navigation")
struct HomeNavigationToolTests {
    @Test("Hidden Home indicators cannot block coordinate-free Home events")
    func bottomGeometryRequirement() {
        #expect(!HomeNavigationAction.home.requiresBottomEdgeCoordinates)
        #expect(!HomeNavigationAction.pageLeft.requiresBottomEdgeCoordinates)
        #expect(!HomeNavigationAction.pageRight.requiresBottomEdgeCoordinates)
        #expect(!HomeNavigationAction.openSettings.requiresBottomEdgeCoordinates)
        #expect(!HomeNavigationAction.appSwitcher.requiresBottomEdgeCoordinates)
    }

    @Test("App launch has one fixed Settings target and no arbitrary bundle or URL input")
    func settingsTarget() async throws {
        #expect(HomeNavigationAction.openSettings.launchBundleID == "com.apple.Preferences")
        for action in HomeNavigationAction.allCases where action != .openSettings {
            #expect(action.launchBundleID == nil)
        }
        let device = NavigationFixture()
        let tool = HomeNavigationTool(device: device)
        for args: [String: JSONValue] in [
            ["action": .string("open_settings"), "bundle_id": .string("com.apple.mobilesafari")],
            ["action": .string("open_settings"), "url": .string("App-prefs:root=WIFI")],
            ["action": .string("open_app")]
        ] {
            await #expect(throws: ScreenControlError.invalidArguments) { try await tool.execute(arguments: args) }
        }
        #expect(await device.calls.isEmpty)
        #expect(tool.approvalSummary(arguments: ["action": .string("open_settings")]).title == "Open Settings")
        _ = try await tool.execute(arguments: ["action": .string("open_settings")])
        #expect(await device.calls == [.openSettings])
    }

    @Test("Only exact navigation commands qualify for the bounded direct path")
    func directCommands() {
        #expect(HomeNavigationAction.directCommand("  Go Home. ") == .home)
        #expect(HomeNavigationAction.directCommand("Open the App Switcher") == .appSwitcher)
        #expect(HomeNavigationAction.directCommand("Swipe one Home Screen page left") == .pageLeft)
        #expect(HomeNavigationAction.directCommand("Swipe one Home page right") == .pageRight)
        #expect(HomeNavigationAction.directCommand("  Open Settings. ") == .openSettings)
        #expect(HomeNavigationAction.directCommand("Please open Settings") == .openSettings)
        for text in ["How do I go home?", "Go Home then send a message", "Don't go home", "Screenshot text: go home", "", "Delete all apps",
                     "How do I open Settings?", "Don't open Settings", "Open Settings and turn off Wi-Fi", "Open Safari", "Screenshot text: Open Settings"] {
            #expect(HomeNavigationAction.directCommand(text) == nil)
        }
    }

    @Test("A navigation session is explicit, finite, stoppable and rejects clock rollback")
    func boundedSession() {
        var session = HomeNavigationSession()
        let beforeStart = session.consume(nowUptime: 10)
        #expect(!beforeStart)
        session.start(nowUptime: 10)
        #expect(session.isActive(nowUptime: 309.99))
        #expect(!session.isActive(nowUptime: 310))
        #expect(!session.isActive(nowUptime: 9))
        #expect(!session.isActive(nowUptime: .nan))
        for _ in 0..<10 {
            let allowed = session.consume(nowUptime: 11)
            #expect(allowed)
        }
        let overLimit = session.consume(nowUptime: 11)
        #expect(!overLimit)
        session.start(nowUptime: 20)
        session.stop()
        let afterStop = session.consume(nowUptime: 21)
        #expect(!afterStop)
        session.start(nowUptime: .infinity)
        #expect(!session.isActive(nowUptime: 21))
    }

    @Test("Fresh bottom-bar detection supports light and dark displays")
    func bottomIndicator() {
        for background: UInt8 in [0, 255] {
            var pixels = [UInt8](repeating: background, count: 200 * 420)
            for y in 410...412 { for x in 70..<130 { pixels[y * 200 + x] = 255 - background } }
            let result = HomeIndicatorRecognizer.locate(pixels: pixels, width: 200, height: 420)
            #expect(result != nil)
            #expect(result?.centerX == 0.5)
            #expect(result?.centerY == 411.5 / 420)
            #expect(result?.width == 0.3)
        }
    }

    @Test("Hidden, ambiguous, non-bottom and malformed captures cannot supply a bottom target")
    func rejectedBottomIndicators() {
        let empty = [UInt8](repeating: 0, count: 200 * 420)
        #expect(HomeIndicatorRecognizer.locate(pixels: empty, width: 200, height: 420) == nil)
        #expect(HomeIndicatorRecognizer.locate(pixels: [], width: 200, height: 420) == nil)
        #expect(HomeIndicatorRecognizer.locate(pixels: empty, width: 420, height: 200) == nil)
        var pixels = empty
        for y in 220...222 { for x in 70..<130 { pixels[y * 200 + x] = 255 } }
        #expect(HomeIndicatorRecognizer.locate(pixels: pixels, width: 200, height: 420) == nil)
        for y in [402, 403, 404, 410, 411, 412] { for x in 70..<130 { pixels[y * 200 + x] = 255 } }
        #expect(HomeIndicatorRecognizer.locate(pixels: pixels, width: 200, height: 420) == nil)
        pixels = empty
        for y in 410...412 { for x in 10..<70 { pixels[y * 200 + x] = 255 } }
        #expect(HomeIndicatorRecognizer.locate(pixels: pixels, width: 200, height: 420) == nil)
    }

    @Test("Home scope guidance stays independent of app screen control and preserves approval")
    func scopeGuidance() {
        let enabled = HomeNavigationTool.configurationContext(enabled: true)
        #expect(enabled.contains("independently of app-scoped screen_* tools"))
        #expect(enabled.contains("wait for approval"))
        #expect(enabled.contains("not permission to execute"))
        let disabled = HomeNavigationTool.configurationContext(enabled: false)
        #expect(disabled.contains("DISABLED"))
        #expect(disabled.contains("Never substitute screen_swipe"))
    }

    @Test("Only the named navigation and Settings-launch actions can reach the device")
    func actions() async throws {
        let device = NavigationFixture()
        let tool = HomeNavigationTool(device: device)
        #expect(tool.requiresApproval)
        for action in HomeNavigationAction.allCases {
            _ = try await tool.execute(arguments: ["action": .string(action.rawValue)])
        }
        #expect(await device.calls == HomeNavigationAction.allCases)
        #expect(tool.definition.parameters["additionalProperties"] == .bool(false))
    }

    @Test("Coordinates, app identifiers, extra arguments and unsupported operations cannot reach the device")
    func invalid() async throws {
        let device = NavigationFixture()
        let tool = HomeNavigationTool(device: device)
        let bad: [[String: JSONValue]] = [[:], ["action": .number(1)], ["action": .string("close_app")],
            ["action": .string("unlock")], ["action": .string("go_home"), "x": .number(0.5)],
            ["action": .string("app_switcher"), "bundle_id": .string("com.apple.Preferences")]]
        for args in bad {
            await #expect(throws: ScreenControlError.invalidArguments) { try await tool.execute(arguments: args) }
        }
        #expect(await device.calls.isEmpty)
    }

    @Test("The real agent loop proposes first and cannot execute until approval")
    func approval() async throws {
        let device = NavigationFixture()
        let tool = HomeNavigationTool(device: device)
        let model = NavigationModel()
        let session = AgentSession(model: model, tools: [tool], iterationLimit: 1)
        guard case .approvalRequired(let pending) = try await session.send("Go Home") else { Issue.record("Approval missing"); return }
        #expect(pending.title == "Return to Home")
        #expect(pending.explanation.contains("neither its pixels nor text go to the model"))
        #expect(await device.calls.isEmpty)
        #expect(try await session.approvePendingAction() == .response("Synthetic dispatch only; no visual success established."))
        #expect(await model.callCount == 1)
        #expect(await device.calls == [.home])
        await #expect(throws: AgentRuntimeError.noPendingApproval) { try await session.approvePendingAction() }
    }

    @Test("Rejecting an action cannot send input")
    func rejection() async throws {
        let device = NavigationFixture()
        let session = AgentSession(model: NavigationModel(), tools: [HomeNavigationTool(device: device)])
        _ = try await session.send("Go Home")
        await session.rejectPendingAction()
        #expect(await device.calls.isEmpty)
    }

    @Test("Owner-authorized navigation executes through the real agent loop without a second card")
    func standingNavigation() async throws {
        let device = NavigationFixture()
        let tool = HomeNavigationTool(device: device, requiresApproval: false)
        let model = NavigationModel()
        let session = AgentSession(model: model, tools: [tool], iterationLimit: 1)
        #expect(try await session.send("Go Home") == .response("Synthetic dispatch only; no visual success established."))
        #expect(await model.callCount == 1)
        #expect(await device.calls == [.home])
        #expect(HomeNavigationTool.configurationContext(enabled: true, standingAccess: true).contains("without asking for permission again"))
        _ = try await session.send("What happened?")
        let messages = await model.lastMessages
        #expect(messages.filter { $0.role == .tool }.count == 1)
        #expect(messages.first { $0.role == .tool }?.toolCallID == "navigation")
        #expect(messages.first { $0.role == .tool }?.content == "Synthetic dispatch only; no visual success established.")
        #expect(await device.calls == [.home])
    }

    @Test("Personal-build authorization defaults on, while Stop and app scope survive relaunch")
    @MainActor func persistedAccess() throws {
        let suite = "PocketAgent.StandingAccessTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = ScreenControlAccessStore(defaults: defaults)
        #expect(initial.appEnabled && initial.navigationEnabled)
        #expect(initial.bundleID == "com.apple.Preferences")
        #expect(initial.mode == .act)
        initial.appEnabled = false
        initial.navigationEnabled = false
        initial.bundleID = "test.allowed.app"
        initial.mode = .guide
        let relaunched = ScreenControlAccessStore(defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(!relaunched.appEnabled && !relaunched.navigationEnabled)
        #expect(relaunched.bundleID == "test.allowed.app")
        #expect(relaunched.mode == .guide)
        relaunched.appEnabled = true
        relaunched.navigationEnabled = true
        #expect(initial.appEnabled && initial.navigationEnabled)
    }

    @Test("Cancellation of navigation or Settings launch targets its exact native operation", arguments: [HomeNavigationAction.home, .openSettings])
    func cancellation(_ command: HomeNavigationAction) async throws {
        let device = WaitingNavigationFixture()
        let tool = HomeNavigationTool(device: device)
        let action = Task { try await tool.execute(arguments: ["action": .string(command.rawValue)]) }
        await device.waitUntilStarted()
        action.cancel()
        await #expect(throws: CancellationError.self) { try await action.value }
        #expect(await device.cancelled == device.started)
    }

    @Test("Live model maps spoken-style commands to fixed navigation proposals only", .enabled(if: ProcessInfo.processInfo.environment["POCKET_AGENT_LIVE_HOME_WIFI"] == "1"))
    func liveCommands() async throws {
        let keyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PocketAgent/model-gateway.key")
        let key = try String(contentsOf: keyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let client = OpenAICompatibleClient(baseURL: "https://\(HomeWiFiModelTransport.serverName)/v1", model: "gpt-oss:20b", apiKey: key, transport: HomeWiFiModelTransport())
        let device = NavigationFixture()
        let tool = HomeNavigationTool(device: device)
        for (request, action) in [("Go Home", HomeNavigationAction.home), ("Open the app switcher", .appSwitcher),
                                  ("Swipe one Home Screen page left", .pageLeft), ("Swipe one Home Screen page right", .pageRight),
                                  ("Open Settings", .openSettings)] {
            let reply = try await client.reply(to: [.init(role: .system, content: AgentSession.defaultSystemPrompt),
                .init(role: .user, content: request + "\n\n[App configuration: " + HomeNavigationTool.configurationContext(enabled: true) + " App-scoped screen_* tools are disabled. This does not disable the separate phone_navigate scope. Only for a request to read or interact inside a selected app, ask the user to enable app-scoped Screen Control.]")], tools: [tool.definition])
            #expect(reply.toolCalls.count == 1)
            #expect(reply.toolCalls.first?.name == "phone_navigate")
            #expect(reply.toolCalls.first?.arguments == ["action": .string(action.rawValue)])
        }
        #expect(await device.calls.isEmpty) // Live model never receives a device.
    }
}

private actor NavigationFixture: HomeNavigationDevice {
    var calls: [HomeNavigationAction] = []
    func navigate(_ action: HomeNavigationAction, operationID: UUID) -> String {
        calls.append(action); return "Synthetic dispatch only; no visual success established."
    }
    func cancel(operationID: UUID) { }
}

private actor NavigationModel: AgentModelClient {
    var replied = false
    var callCount = 0
    var lastMessages: [ModelMessage] = []
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) -> ModelReply {
        callCount += 1
        lastMessages = messages
        if replied { return .init(content: "Dispatch reported; please inspect the phone.") }
        replied = true
        return .init(toolCalls: [.init(id: "navigation", name: "phone_navigate", arguments: ["action": .string("go_home")])])
    }
}

private actor WaitingNavigationFixture: HomeNavigationDevice {
    var started: UUID?
    var cancelled: UUID?
    var startWaiter: CheckedContinuation<Void, Never>?
    var actionWaiter: CheckedContinuation<String, Error>?
    func navigate(_ action: HomeNavigationAction, operationID: UUID) async throws -> String {
        started = operationID
        return try await withCheckedThrowingContinuation { continuation in
            actionWaiter = continuation; startWaiter?.resume(); startWaiter = nil
        }
    }
    func waitUntilStarted() async {
        if actionWaiter != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func cancel(operationID: UUID) {
        cancelled = operationID
        actionWaiter?.resume(throwing: CancellationError()); actionWaiter = nil
    }
}
