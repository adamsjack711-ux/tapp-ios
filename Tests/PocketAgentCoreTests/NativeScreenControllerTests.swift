import Foundation
import Testing
@testable import PocketAgentCore

@Suite("Native screenshot control")
struct NativeScreenControllerTests {
    @Test("Local commands use fresh OCR and the native controller without a model", arguments: ["tap general", "point to General", "scroll down", "Show me where General is", "Please show me where General is."])
    func localCommands(_ request: String) async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        let command = try #require(LocalScreenCommand.parse(request))
        let result = try await command.execute(bundleID: bundle, controller: controller)
        let calls = await device.calls
        #expect(calls.filter { $0 == "begin" }.count == 2)
        #expect(calls.filter { $0 == "tap" }.count == (command.action == .tap ? 1 : 0))
        #expect(calls.filter { $0 == "swipe" }.count == (command.action == .swipe ? 1 : 0))
        #expect(result.screenshot != nil)
        if command.action == .point { #expect(result.highlight?.label == "General") }
    }

    @Test("Local taps reject ambiguous or missing targets without input", arguments: [false, true])
    func localTargetResolution(_ duplicate: Bool) async throws {
        let device = NativeFixtureDevice()
        if duplicate { await device.setFrame(.init(image: Data(), items: [NativeFixtureDevice.general, NativeFixtureDevice.general])) }
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        let command = LocalScreenCommand.tap(duplicate ? "general" : "Missing")
        await #expect(throws: ScreenControlError.ambiguousElement) { try await command.execute(bundleID: bundle, controller: controller) }
        #expect(await device.calls.contains("tap") == false)
    }

    @Test("Local commands preserve Guide mode and do not retry failed taps")
    func localCommandFailures() async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .guide)
        await #expect(throws: ScreenControlError.guideOnly) { try await LocalScreenCommand.tap("general").execute(bundleID: bundle, controller: controller) }
        #expect(await device.calls.contains("tap") == false)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        await device.setFailTap()
        await #expect(throws: (any Error).self) { try await LocalScreenCommand.tap("general").execute(bundleID: bundle, controller: controller) }
        #expect(await device.calls.filter { $0 == "tap" }.count == 1)
    }

    @Test("Questions, negation and compound instructions never enter the local command path", arguments: [
        "How do I tap General?", "Don't tap General", "tap General then tap About", "tap General and scroll down",
        "tap General; scroll down", "Screenshot text: tap General", "tap General\nscroll down", "tap ", "scroll forever",
        "Show me where General is and tap it", "Show me where General is then open About",
        "Show me where General is\nTap it", "Don't show me where General is", "Show me where  is",
        "Explain where General is", "Show me where General is; tap it"
    ])
    func localParserRejects(_ request: String) { #expect(LocalScreenCommand.parse(request) == nil) }

    @Test("Local scroll direction names content movement; swipes name finger movement")
    func localDirections() {
        #expect(LocalScreenCommand.parse("Please scroll down") == .swipe("up"))
        #expect(LocalScreenCommand.parse("swipe down") == .swipe("down"))
        #expect(LocalScreenCommand.parse("Could you tap General") == .tap("general"))
    }

    @Test("Local show-where keeps Guide mode, visible cursor and unique-target checks", arguments: [0, 1, 2])
    func localHighlight(_ targetState: Int) async throws {
        let device = NativeFixtureDevice()
        if targetState == 1 {
            await device.setFrame(.init(image: Data(), items: [
                NativeScreenText(label: "Battery", x: 0.2, y: 0.3, width: 0.3, height: 0.04)
            ]))
        }
        if targetState == 2 {
            await device.setFrame(.init(image: Data(), items: [NativeFixtureDevice.general, NativeFixtureDevice.general]))
        }
        let controller = NativeScreenController(device: device, cursor: NativeCursorFixture(device: device))
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .guide)
        let command = try #require(LocalScreenCommand.parse("Show me where General is"))
        if targetState == 0 {
            _ = try await command.execute(bundleID: bundle, controller: controller)
            #expect(await device.calls.filter { $0 == "cursor-arrived" }.count == 1)
        } else {
            await #expect(throws: ScreenControlError.ambiguousElement) {
                try await command.execute(bundleID: bundle, controller: controller)
            }
            #expect(await device.calls.contains("cursor-arrived") == false)
        }
        #expect(await device.calls.contains("tap") == false)
    }

    @Test("Requested gestures finish through the agent without a permission card", arguments: [ScreenAction.tap, .hold, .drag])
    func requestedGestures(_ action: ScreenAction) async throws {
        let device = NativeHeldGestureFixture()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        let tools = [ScreenAction.read, action].map {
            ScreenTool(action: $0, controller: controller, usesNativeOCR: true, approvalPolicy: .requestedActions)
        }
        let session = AgentSession(model: RequestedGestureModel(action: action), tools: tools)
        #expect(try await session.send("Perform the requested fixture gesture") == .response("Complete"))
        #expect(await device.calls.contains(action == .tap ? "tap" : action == .hold ? "hold:Start" : "drag:Start:End"))
        await #expect(throws: AgentRuntimeError.noPendingApproval) { try await session.approvePendingAction() }
        await controller.disable()
        let readSession = AgentSession(model: NativeReadModel(), tools: tools)
        await #expect(throws: ScreenControlError.disabled) { try await readSession.send("Read again") }
    }

    @Test("AI hold and drag use observed targets and read their result",arguments:[ScreenAction.hold,.drag])
    func heldGestures(_ action:ScreenAction) async throws {
        let device=NativeHeldGestureFixture()
        let controller=NativeScreenController(device:device)
        try await controller.configure(enabled:true,allowedBundleID:bundle,mode:.act)
        let read=try await controller.perform(.read,arguments:readArgs)
        var args=tapArgs(read,label:"Start")
        if action == .drag { args["destination_label"] = .string("End") }
        _ = try await controller.perform(action,arguments:args)
        #expect(await device.calls.suffix(6) == ["begin","open","capture",action == .hold ? "hold:Start" : "drag:Start:End","capture","finish"])
        await #expect(throws:ScreenControlError.staleScreen) { try await controller.perform(action,arguments:args) }
    }

    @Test("Drag rejects invented or duplicate destinations and coordinates before input",arguments:0..<3)
    func invalidDrag(_ kind:Int) async throws {
        let device=NativeHeldGestureFixture(duplicate:kind==1)
        let controller=NativeScreenController(device:device)
        try await controller.configure(enabled:true,allowedBundleID:bundle,mode:.act)
        let read=try await controller.perform(.read,arguments:readArgs)
        var args=tapArgs(read,label:"Start")
        args["destination_label"] = .string(kind==0 ? "Invented" : "End")
        if kind==2 { args["x"] = .number(0.5) }
        await #expect(throws:ScreenControlError.self) { try await controller.perform(.drag,arguments:args) }
        #expect(await device.calls.allSatisfy { !$0.hasPrefix("drag:") })
    }

    private let bundle = "com.apple.Preferences"
    private var readArgs: [String: JSONValue] { ["bundle_id": .string(bundle)] }
    private func tapArgs(_ result: ScreenResult, label: String = "General") -> [String: JSONValue] {
        ["bundle_id": .string(bundle), "observation_id": .string(result.observationID), "label": .string(label)]
    }

    @Test("OCR edge rounding is tolerated while moved edges and changed labels remain stale")
    func ocrEdgeRounding() {
        let base=NativeScreenText(label:"Bottom left 2",x:0.0631,y:0.8343,width:0.2114,height:0.0145)
        let rounded=NativeScreenText(label:base.label,x:0.0599,y:0.8328,width:0.2177,height:0.0160)
        let moved=NativeScreenText(label:base.label,x:0.0731,y:base.y,width:base.width,height:base.height)
        let changed=NativeScreenText(label:"Bottom left 3",x:base.x,y:base.y,width:base.width,height:base.height)
        let original=NativeScreenFrame(image:Data(),items:[base])
        #expect(original.sameContent(as:NativeScreenFrame(image:Data(),items:[rounded])))
        #expect(!original.sameContent(as:NativeScreenFrame(image:Data(),items:[moved])))
        #expect(!original.sameContent(as:NativeScreenFrame(image:Data(),items:[changed])))
        #expect(NativeScreenText(label:"Bottom right done",x:0.6782,y:0.8343,width:0.2965,height:0.016).cursorAnchor.x < 0.9)
    }

    @Test("Revalidating devices avoid a redundant capture but still verify immediately before input")
    func revalidatedTapPipeline() async throws {
        let device=RevalidatingNativeFixture()
        let controller=NativeScreenController(device:device)
        try await controller.configure(enabled:true,allowedBundleID:bundle,mode:.act)
        let read=try await controller.perform(.read,arguments:readArgs)
        _ = try await controller.perform(.tap,arguments:tapArgs(read))
        #expect(await device.calls.suffix(6) == ["open","prepare","revalidate","tap","capture","finish"])
        #expect(await device.calls.filter { $0 == "capture" }.count == 2)
    }

    @Test("Fresh device-side validation still blocks changed targets, duplicate labels and permission prompts",arguments:[0,1,2])
    func revalidationBlocksChanges(_ kind:Int) async throws {
        let device=RevalidatingNativeFixture()
        let controller=NativeScreenController(device:device)
        try await controller.configure(enabled:true,allowedBundleID:bundle,mode:.act)
        let read=try await controller.perform(.read,arguments:readArgs)
        let original=NativeFixtureDevice.general
        let items=kind==0 ? [NativeScreenText(label:"General",x:0.4,y:0.3,width:0.3,height:0.04)] :
            kind==1 ? [original,original] : [NativeScreenText(label:"Allow access",x:0.2,y:0.3,width:0.3,height:0.04)]
        await device.setFrame(NativeScreenFrame(image:Data([4]),items:items))
        await #expect(throws:ScreenControlError.self) { try await controller.perform(.tap,arguments:tapArgs(read)) }
        #expect(await device.calls.contains("revalidate"))
        #expect(await device.calls.contains("tap") == false)
        #expect(await device.calls.last == "finish")
    }

    @Test("Tapp arrival precedes both local and model-selected taps and the fresh result capture", arguments: [false, true])
    func cursorPipeline(_ localCommand: Bool) async throws {
        let device = NativeFixtureDevice()
        let cursor = NativeCursorFixture(device: device)
        let controller = NativeScreenController(device: device, cursor: cursor)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        if localCommand {
            let command = try #require(LocalScreenCommand.parse("tap General"))
            _ = try await command.execute(bundleID: bundle, controller: controller)
        } else {
            let read = try await controller.perform(.read, arguments: readArgs)
            _ = try await controller.perform(.tap, arguments: tapArgs(read))
        }
        #expect(await device.calls.suffix(7) == ["begin","open","capture","cursor-arrived","tap","capture","finish"])
    }

    @Test("A Tapp connection failure blocks both local and model-selected taps", arguments: [false, true])
    func cursorFailure(_ localCommand: Bool) async throws {
        let device = NativeFixtureDevice()
        let cursor = NativeCursorFixture(device: device, fail: true)
        let controller = NativeScreenController(device: device, cursor: cursor)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        if localCommand {
            let command = try #require(LocalScreenCommand.parse("tap General"))
            await #expect(throws: NativeScreenError.self) { try await command.execute(bundleID: bundle, controller: controller) }
        } else {
            let read = try await controller.perform(.read, arguments: readArgs)
            await #expect(throws: NativeScreenError.self) { try await controller.perform(.tap, arguments: tapArgs(read)) }
        }
        #expect(await device.calls.contains("tap") == false)
        #expect(await device.calls.last == "finish")
    }

    @Test("Disabled, wrong-app and guide-mode writes cannot start a device session")
    func guardrails() async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        await #expect(throws: ScreenControlError.disabled) { try await controller.perform(.read, arguments: readArgs) }
        try await controller.configure(enabled: true, allowedBundleID: bundle)
        await #expect(throws: ScreenControlError.wrongApp) {
            try await controller.perform(.read, arguments: ["bundle_id": .string("com.apple.reminders")])
        }
        for action in [ScreenAction.tap, .swipe, .type] {
            await #expect(throws: ScreenControlError.guideOnly) { try await controller.perform(action, arguments: readArgs) }
        }
        #expect(await device.calls.isEmpty)
    }

    @Test("A read returns local image and honest OCR; a point never sends input")
    func readAndPoint() async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle)
        let read = try await controller.perform(.read, arguments: readArgs)
        #expect(read.text.contains("not an accessibility tree"))
        #expect(read.screenshot == Data([1, 2, 3]))
        let point = try await controller.perform(.point, arguments: tapArgs(read))
        #expect(point.highlight?.label == "General")
        #expect(point.highlight?.x == 0.2)
        #expect(await device.calls == ["begin", "open", "capture", "finish", "begin", "open", "capture", "finish"])
    }

    @Test("Approved tap is single-use and returns a fresh capture")
    func tapAndReplay() async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        let read = try await controller.perform(.read, arguments: readArgs)
        let result = try await controller.perform(.tap, arguments: tapArgs(read))
        #expect(result.observationID != read.observationID)
        #expect(await device.calls.filter { $0 == "tap" }.count == 1)
        await #expect(throws: ScreenControlError.staleScreen) { try await controller.perform(.tap, arguments: tapArgs(read)) }
        #expect(await device.calls.last == "finish")
    }

    @Test("Changed screens and duplicate labels cannot receive a tap")
    func staleAndAmbiguous() async throws {
        for duplicate in [false, true] {
            let device = NativeFixtureDevice()
            let controller = NativeScreenController(device: device)
            try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
            if duplicate { await device.setFrame(.init(image: Data(), items: [NativeFixtureDevice.general, NativeFixtureDevice.general])) }
            let read = try await controller.perform(.read, arguments: readArgs)
            if !duplicate { await device.setFrame(.init(image: Data(), items: [NativeScreenText(label: "Changed", x: 0.2, y: 0.3, width: 0.3, height: 0.04)])) }
            await #expect(throws: duplicate ? ScreenControlError.ambiguousElement : .staleScreen) {
                try await controller.perform(.tap, arguments: tapArgs(read))
            }
            #expect(await device.calls.contains("tap") == false)
            #expect(await device.calls.last == "finish")
        }
    }

    @Test("Failed input is cleaned up and never automatically retried")
    func failedInput() async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        let read = try await controller.perform(.read, arguments: readArgs)
        await device.setFailTap()
        await #expect(throws: NativeScreenError.self) { try await controller.perform(.tap, arguments: tapArgs(read)) }
        await #expect(throws: ScreenControlError.staleScreen) { try await controller.perform(.tap, arguments: tapArgs(read)) }
        #expect(await device.calls.filter { $0 == "tap" }.count == 1)
        #expect(await device.calls.last == "finish")
    }

    @Test("Permission prompts block reads and consume future-action eligibility after an input")
    func permissions() async throws {
        let prompt = NativeScreenFrame(image: Data(), items: [.init(label: "Would Like to Allow Access", x: 0.1, y: 0.4, width: 0.8, height: 0.05)])
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        await device.setFrame(prompt)
        await #expect(throws: ScreenControlError.blockedByAlert) { try await controller.perform(.read, arguments: readArgs) }
        await device.setFrame(NativeFixtureDevice.normal)
        let read = try await controller.perform(.read, arguments: readArgs)
        await device.setAfterTap(prompt)
        let tapped = try await controller.perform(.tap, arguments: tapArgs(read))
        #expect(tapped.outcome.contains("Handle it yourself"))
        await #expect(throws: ScreenControlError.staleScreen) { try await controller.perform(.tap, arguments: tapArgs(tapped)) }
    }

    @Test("Typing and inferred accessibility types are rejected before contact")
    func unsupportedInput() async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        await #expect(throws: NativeScreenError.self) { try await controller.perform(.type, arguments: readArgs) }
        let tool = ScreenTool(action: .tap, controller: controller, usesNativeOCR: true)
        guard case .object(let properties) = tool.definition.parameters["properties"],
              case .object(let type) = properties["element_type"] else { Issue.record("Missing tool schema"); return }
        #expect(type["enum"] == .array([.string("StaticText")]))
        #expect(await device.calls.isEmpty)
    }

    @Test("Actual agent approval is required before native screenshot access")
    func approval() async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle)
        let session = AgentSession(model: NativeReadModel(), tools: [ScreenTool(action: .read, controller: controller, usesNativeOCR: true)])
        guard case .approvalRequired = try await session.send("Read Settings") else { Issue.record("Expected approval"); return }
        #expect(await device.calls.isEmpty)
        _ = try await session.approvePendingAction()
        #expect(await device.calls == ["begin", "open", "capture", "finish"])
    }

    @Test("Standing access reads and navigates without any repeat approval card")
    func standingAccess() async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        let tools = [ScreenAction.read, .tap].map {
            ScreenTool(action: $0, controller: controller, usesNativeOCR: true, approvalPolicy: .standingAccess)
        }
        let session = AgentSession(model: NativeNavigationModel(label: "General"), tools: tools)
        #expect(try await session.send("Open General in Settings") == .response("Synthetic navigation complete"))
        #expect(await device.calls.filter { $0 == "tap" }.count == 1)
        await #expect(throws: AgentRuntimeError.noPendingApproval) { try await session.approvePendingAction() }
    }

    @Test("Standing access never re-enables a controller the user stopped")
    func stoppedStandingAccess() async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        await controller.disable()
        let session = AgentSession(model: NativeReadModel(), tools: [
            ScreenTool(action: .read, controller: controller, approvalPolicy: .standingAccess)
        ])
        await #expect(throws: ScreenControlError.disabled) { try await session.send("Read Settings") }
        #expect(await device.calls.isEmpty)
    }

    @Test("Unknown and consequential taps still stop for review after an automatic read", arguments: ["Send", "Delete", "Allow", "Unknown control"])
    func consequentialReview(_ label: String) async throws {
        let device = NativeFixtureDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        let tools = [ScreenAction.read, .tap].map {
            ScreenTool(action: $0, controller: controller, approvalPolicy: .standingAccess)
        }
        let session = AgentSession(model: NativeNavigationModel(label: label), tools: tools)
        guard case .approvalRequired(let pending) = try await session.send("Synthetic consequence test") else {
            Issue.record("Consequence review was bypassed"); return
        }
        #expect(pending.toolName == "screen_tap")
        #expect(await device.calls == ["begin", "open", "capture", "finish"])
    }

    @Test("Standing policy is app-specific and cannot grant typing or security access")
    func standingPolicy() {
        let policy = ScreenApprovalPolicy.standingAccess
        #expect(!policy.requiresApproval(action: .read, arguments: readArgs))
        #expect(!policy.requiresApproval(action: .point, arguments: readArgs))
        #expect(!policy.requiresApproval(action: .swipe, arguments: readArgs))
        #expect(policy.requiresApproval(action: .type, arguments: readArgs))
        #expect(policy.requiresApproval(action: .tap, arguments: ["bundle_id": .string("other.app"), "label": .string("General")]))
        for label in ["Allow", "Trust", "Delete", "Erase All Content and Settings", "Send", "Buy", "Save", "Done", "Continue", "General\nAllow"] {
            #expect(policy.requiresApproval(action: .tap, arguments: ["bundle_id": .string(bundle), "label": .string(label)]))
        }
    }

    @Test("OCR order jitter is ignored, content and geometry changes are not")
    func frameComparison() {
        let other = NativeScreenText(label: "About", x: 0.2, y: 0.4, width: 0.2, height: 0.04)
        let a = NativeScreenFrame(image: Data(), items: [NativeFixtureDevice.general, other])
        let b = NativeScreenFrame(image: Data([9]), items: [other, NativeFixtureDevice.general])
        #expect(a.sameContent(as: b))
        #expect(!a.sameContent(as: NativeFixtureDevice.normal))
        #expect(!NativeScreenText(label: "Invalid", x: .nan, y: 0.3, width: 0.2, height: 0.1).valid)
    }

    @Test("Disabling an in-flight operation cancels its exact session and prevents subsequent input")
    func stopInFlight() async throws {
        let device = PausingNativeDevice()
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle, mode: .act)
        let task = Task { try await controller.perform(.read, arguments: readArgs) }
        await device.waitUntilStarted()
        await #expect(throws: ScreenControlError.busy) { try await controller.perform(.read, arguments: readArgs) }
        await controller.disable()
        await #expect(throws: ScreenControlError.disabled) { try await task.value }
        #expect(await device.cancelledID == device.startedID)
        #expect(await device.calls == ["begin", "cancel", "finish"])
    }

    @Test("Live model uses the native approval path and OCR result", .enabled(if: ProcessInfo.processInfo.environment["POCKET_AGENT_LIVE_HOME_WIFI"] == "1"))
    func liveNativeAgentLoop() async throws {
        let keyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PocketAgent/model-gateway.key")
        let key = try String(contentsOf: keyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let client = OpenAICompatibleClient(baseURL: "https://\(HomeWiFiModelTransport.serverName)/v1", model: "gpt-oss:20b", apiKey: key, transport: HomeWiFiModelTransport())
        let device = NativeFixtureDevice() // Synthetic Settings only; no phone contacted.
        let controller = NativeScreenController(device: device)
        try await controller.configure(enabled: true, allowedBundleID: bundle)
        let session = AgentSession(model: client, tools: [ScreenTool(action: .read, controller: controller, usesNativeOCR: true)])
        guard case .approvalRequired(let pending) = try await session.send("Native Guide me is enabled for com.apple.Preferences. Read its screen once, then summarize the text. Do not take any further actions.") else {
            Issue.record("The live model did not request the screen read"); return
        }
        #expect(pending.toolName == "screen_read")
        #expect(await device.calls.isEmpty)
        guard case .response(let answer) = try await session.approvePendingAction() else {
            Issue.record("Expected a summary after the approved read"); return
        }
        #expect(answer.localizedCaseInsensitiveContains("General"))
        #expect(await device.calls == ["begin", "open", "capture", "finish"])
    }
}

private actor NativeHeldGestureFixture:NativeScreenGestureDevice {
    var calls=[String]()
    let duplicate:Bool
    init(duplicate:Bool=false) { self.duplicate=duplicate }
    func begin(bundleID:String,operationID:UUID) { calls.append("begin") }
    func openAllowedApp() { calls.append("open") }
    func captureFrame() -> NativeScreenFrame {
        calls.append("capture")
        let end=NativeScreenText(label:"End",x:0.55,y:0.65,width:0.2,height:0.04)
        return .init(image:Data(),items:[.init(label:"Start",x:0.2,y:0.3,width:0.2,height:0.04),end]+(duplicate ? [end] : []))
    }
    func hold(_ target:NativeScreenText) { calls.append("hold:\(target.label)") }
    func drag(_ target:NativeScreenText,to destination:NativeScreenText) { calls.append("drag:\(target.label):\(destination.label)") }
    func tap(_ target:NativeScreenText) { calls.append("tap") }
    func swipe(direction:String) { calls.append("swipe") }
    func finish() -> String? { calls.append("finish");return nil }
    func cancel(operationID:UUID) { calls.append("cancel") }
}

private actor RevalidatingNativeFixture:NativeScreenRevalidatingTapDevice {
    var calls=[String]()
    var frame=NativeFixtureDevice.normal
    var previous:NativeScreenFrame?
    func setFrame(_ value:NativeScreenFrame) { frame=value }
    func begin(bundleID:String,operationID:UUID) { calls.append("begin") }
    func openAllowedApp() { calls.append("open") }
    func captureFrame() -> NativeScreenFrame { calls.append("capture"); return frame }
    func prepareTapObservation(_ frame:NativeScreenFrame) { calls.append("prepare"); previous=frame }
    func tap(_ target:NativeScreenText) throws {
        calls.append("revalidate")
        guard let previous else { throw ScreenControlError.staleScreen }
        _ = try frame.revalidatedTapTarget(target,matching:previous)
        calls.append("tap")
    }
    func swipe(direction:String) { calls.append("swipe") }
    func finish() -> String? { calls.append("finish"); return nil }
    func cancel(operationID:UUID) { calls.append("cancel") }
}

private actor NativeFixtureDevice: NativeScreenDevice {
    static let general = NativeScreenText(label: "General", x: 0.2, y: 0.3, width: 0.3, height: 0.04)
    static let normal = NativeScreenFrame(image: Data([1, 2, 3]), items: [general])
    var calls: [String] = []
    var frame = normal
    var afterTap: NativeScreenFrame?
    var failTap = false
    func recordCursor() { calls.append("cursor-arrived") }
    func setFrame(_ value: NativeScreenFrame) { frame = value }
    func setAfterTap(_ value: NativeScreenFrame) { afterTap = value }
    func setFailTap() { failTap = true }
    func begin(bundleID: String, operationID: UUID) { calls.append("begin") }
    func openAllowedApp() { calls.append("open") }
    func captureFrame() -> NativeScreenFrame { calls.append("capture"); return frame }
    func tap(_ target: NativeScreenText) throws {
        calls.append("tap")
        if failTap { throw NativeScreenError.unreadable }
        if let afterTap { frame = afterTap }
    }
    func swipe(direction: String) { calls.append("swipe") }
    func finish() -> String? { calls.append("finish"); return nil }
    func cancel(operationID: UUID) { calls.append("cancel") }
}

private actor NativeCursorFixture: NativeScreenCursor {
    let device: NativeFixtureDevice
    let fail: Bool
    init(device: NativeFixtureDevice, fail: Bool = false) { self.device = device; self.fail = fail }
    func isEnabled() -> Bool { true }
    func move(to target: NativeScreenText) async throws {
        if fail { throw NativeScreenError.unreadable }
        await device.recordCursor()
    }
    func cancelMotion() { }
}

private actor NativeReadModel: AgentModelClient {
    private var replied = false
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) -> ModelReply {
        if replied { return .init(content: "Read complete") }
        replied = true
        return .init(content: "", toolCalls: [.init(id: "native-read", name: "screen_read", arguments: ["bundle_id": .string("com.apple.Preferences")])])
    }
}

private actor NativeNavigationModel: AgentModelClient {
    let label: String
    var step = 0
    init(label: String) { self.label = label }
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) throws -> ModelReply {
        defer { step += 1 }
        if step == 0 {
            return .init(toolCalls: [.init(id: "read", name: "screen_read", arguments: ["bundle_id": .string("com.apple.Preferences")])])
        }
        if step == 1 {
            let result = try JSONDecoder().decode([String: JSONValue].self, from: Data(messages.last!.content.utf8))
            return .init(toolCalls: [.init(id: "tap", name: "screen_tap", arguments: ["bundle_id": .string("com.apple.Preferences"),
                "observation_id": result["observation_id"]!, "label": .string(label)])])
        }
        return .init(content: "Synthetic navigation complete")
    }
}

private actor PausingNativeDevice: NativeScreenDevice {
    var calls: [String] = []
    var startedID: UUID?
    var cancelledID: UUID?
    private var resume: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func begin(bundleID: String, operationID: UUID) async {
        startedID = operationID; calls.append("begin")
        await withCheckedContinuation { continuation in
            resume = continuation; started?.resume(); started = nil
        }
    }
    func waitUntilStarted() async {
        if startedID != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func openAllowedApp() { calls.append("open") }
    func captureFrame() -> NativeScreenFrame { calls.append("capture"); return NativeFixtureDevice.normal }
    func tap(_ target: NativeScreenText) { calls.append("tap") }
    func swipe(direction: String) { calls.append("swipe") }
    func finish() -> String? { calls.append("finish"); return nil }
    func cancel(operationID: UUID) {
        cancelledID = operationID; calls.append("cancel"); resume?.resume(); resume = nil
    }
}

private actor RequestedGestureModel: AgentModelClient {
    let action: ScreenAction
    var step = 0
    init(action: ScreenAction) { self.action = action }
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) throws -> ModelReply {
        defer { step += 1 }
        if step == 0 { return .init(toolCalls: [.init(id: "read", name: "screen_read", arguments: ["bundle_id": .string("com.apple.Preferences")])]) }
        if step == 1 {
            let result = try JSONDecoder().decode([String: JSONValue].self, from: Data(messages.last!.content.utf8))
            var arguments: [String: JSONValue] = ["bundle_id": .string("com.apple.Preferences"), "observation_id": result["observation_id"]!, "label": .string("Start")]
            if action == .drag { arguments["destination_label"] = .string("End") }
            return .init(toolCalls: [.init(id: "gesture", name: action.rawValue, arguments: arguments)])
        }
        return .init(content: "Complete")
    }
}
