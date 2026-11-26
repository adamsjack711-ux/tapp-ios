import Foundation
import Combine
import UIKit

@MainActor
final class AppModel: ObservableObject {
    enum WorkPhase {
        case thinking, readingScreenshot, approvedAction, stopping
        var title: String {
            switch self {
            case .thinking: return "Thinking it through"
            case .readingScreenshot: return "Reading your screenshot"
            case .approvedAction: return "Working on your approved action"
            case .stopping: return "Stopping…"
            }
        }
        var detail: String {
            switch self {
            case .thinking: return "Waiting for the model’s next step."
            case .readingScreenshot: return "Extracting visible text on this device."
            case .approvedAction: return "Waiting for the result. No automatic retries."
            case .stopping: return "An action already sent may have completed."
            }
        }
    }
    struct ChatItem: Identifiable, Equatable {
        enum Speaker { case user, agent, status }

        let id = UUID()
        let speaker: Speaker
        let text: String
    }

    @Published var messages: [ChatItem] = []
    @Published var draft = ""
    @Published var attachedImageData: Data?
    @Published var pendingApproval: PendingApproval?
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var workPhase: WorkPhase = .thinking
    @Published private(set) var lastModelResponseAt: Date?

    private let session: AgentSession
    let screen: ScreenControlModel
    private let allowance = BackgroundAllowance()
    private var task: Task<Void, Never>?
    private var screenChanges: AnyCancellable?

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--use-local-ollama") {
            SettingsKeys.useLocalOllama()
        }
        #endif
        let modelClient = ConfiguredModelClient()
        let screenModel = ScreenControlModel()
        screen = screenModel
        session = AgentSession(
            model: modelClient,
            tools: [CurrentTimeTool(), CreateReminderTool(), HomeNavigationTool(device: NativeControlModel.shared, requiresApproval: false), AppSwitcherTool(device:NativeControlModel.shared, requiresApproval:false)] + [ScreenAction.read, .point, .tap, .hold, .drag, .swipe].map {
                ScreenTool(action: $0, controller: screenModel.controller, usesNativeOCR: true, approvalPolicy: .requestedActions, onResult: { [weak screenModel] result in
                    await screenModel?.receiveAgentResult(result)
                }) as any AgentTool
            }
        )
        screenChanges = screen.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview-captured-screen") {
            do {
                try screen.loadRecordedSimulatorCapture()
                messages.append(ChatItem(speaker: .status, text: "Recorded simulator test capture. This previews the guide UI; live screen control is off."))
            } catch { errorMessage = "The recorded simulator capture could not be loaded." }
        }
        if ProcessInfo.processInfo.arguments.contains("--test-local-model"),
           ProcessInfo.processInfo.arguments.contains("--use-local-ollama") {
            draft = "Use the current_time tool once, then tell me the time it returned. Do not use any other tool."
            send()
        }
        #endif
    }

    #if DEBUG
    /// Runs the same chat dispatch as Send, restricted to the disposable fixture.
    func runRequestedSwitcherDiagnostic() async {
        let motionOnly=ProcessInfo.processInfo.arguments.contains("--test-switcher-motion-chat")
        let cornersOnly=ProcessInfo.processInfo.arguments.contains("--test-switcher-corners-chat")
        let aiNavigation=ProcessInfo.processInfo.arguments.contains("--test-switcher-ai-chat")
        let aiShow=ProcessInfo.processInfo.arguments.contains("--test-switcher-ai-show-chat")
        let heldGestures=ProcessInfo.processInfo.arguments.contains("--test-tapp-held-gestures")
        let instantEntry=ProcessInfo.processInfo.arguments.contains("--test-switcher-instant-chat")
        guard motionOnly || cornersOnly || aiNavigation || aiShow || heldGestures || instantEntry || ProcessInfo.processInfo.arguments.contains("--test-switcher-long-chat") else { return }
        guard messages.isEmpty,canSend == false else { return }
        // Launch-time SwiftUI tasks can precede foreground activation.
        // Wait before dispatch; never retry a sent command or gesture.
        for _ in 0..<30 {
            if UIApplication.shared.applicationState == .active { break }
            do { try await Task.sleep(for:.milliseconds(100)) } catch { return }
        }
        guard UIApplication.shared.applicationState == .active,!Task.isCancelled,messages.isEmpty else { return }
        if heldGestures {
            do { try await TappCursorModel.shared.runHeldGestureDiagnostic() }
            catch { errorMessage=error.localizedDescription }
            return
        }
        draft = aiShow ? "Tapp navigate: Bring up my open apps so I can choose one." : aiNavigation ? "Tapp navigate: Show my open apps, browse one older card, then come back." : (cornersOnly || instantEntry) ? "Show my open apps" : motionOnly ? "Show my open apps then swipe right then swipe left" : "Show my open apps then swipe right then swipe left then reopen Tapp Click Test then close Tapp Click Test"
        send()
    }
    #endif

    var canSend: Bool {
        !isWorking && !screen.isWorking && pendingApproval == nil && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImageData != nil)
    }

    func attachImage(_ data: Data?) {
        attachedImageData = data
    }

    func modelConfigurationChanged() {
        lastModelResponseAt = nil
    }

    func send() {
        guard canSend else { return }
        TappCursorModel.shared.wake()
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = text.isEmpty ? "Please explain what is shown in this screenshot." : text
        let imageData = attachedImageData

        draft = ""
        attachedImageData = nil
        pendingApproval = nil
        errorMessage = nil
        workPhase = imageData == nil ? .thinking : .readingScreenshot
        messages.append(ChatItem(speaker: .user, text: prompt))
        isWorking = true

        beginAllowance()
        task = Task {
            defer { isWorking = false; task = nil; allowance.end() }
            do {
                let screenText: String?
                if let imageData {
                    screenText = try await ImageOCRService.recognizeText(in: imageData)
                } else {
                    screenText = nil
                }
                try Task.checkCancellation()
                workPhase = .thinking
                if imageData == nil, prompt.lowercased() == "test cursor click" {
                    PointerClickModel.shared.showProof = true
                    messages.append(ChatItem(speaker: .status, text: "Opened the inert cursor-click test. No message will be sent."))
                    return
                }
                if imageData == nil,prompt.lowercased().hasPrefix("test tapp:") {
                    workPhase = .approvedAction
                    allowance.end() // The bounded Tapp test owns its continued task.
                    let request=String(prompt.dropFirst("test tapp:".count)).trimmingCharacters(in:.whitespacesAndNewlines)
                    let result=try await TappCursorModel.shared.performAITest(request:request)
                    if !Task.isCancelled { messages.append(ChatItem(speaker:.status,text:result)) }
                    return
                }
                if imageData == nil, let draft = MessageRequest.parseDraftCommand(prompt) {
                    try MessageComposeModel.shared.prepare(draft)
                    messages.append(ChatItem(speaker: .status, text: "Message prepared in the system composer. No message has been sent. Recipient and text stayed on this phone."))
                    return
                }
                if imageData == nil, let plan = AppSwitcherRequest.plan(prompt), NativeControlModel.shared.hasActiveNavigationSession {
                    workPhase = .approvedAction
                    allowance.end()
                    let result = try await NativeControlModel.shared.controlSwitcherPlan(plan,operationID:UUID())
                    if !Task.isCancelled { messages.append(ChatItem(speaker:.status,text:result)) }
                    return
                }
                if imageData == nil,let request=TappNavigationPlanner.request(in:prompt) {
                    guard NativeControlModel.shared.hasActiveNavigationSession else { throw ScreenControlError.disabled }
                    let plan=try await TappNavigationPlanner(model:ConfiguredModelClient()).plan(request:request)
                    try Task.checkCancellation()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--test-switcher-ai-show-chat") || ProcessInfo.processInfo.arguments.contains("--test-switcher-ai-chat") {
                        let evidence:[String:Any]=["request":request,"steps":plan.map(\.action),"source":"configured-model-tool-call","time":Date.now.timeIntervalSince1970]
                        try JSONSerialization.data(withJSONObject:evidence,options:.prettyPrinted).write(to:URL.documentsDirectory.appendingPathComponent("tapp-navigation-ai-plan.json"),options:.atomic)
                    }
                    #endif
                    messages.append(ChatItem(speaker:.status,text:"Tapp's navigation plan: "+plan.map(\.action).joined(separator:" → ")))
                    workPhase = .approvedAction
                    allowance.end()
                    let result=try await NativeControlModel.shared.controlSwitcherPlan(plan,operationID:UUID())
                    if !Task.isCancelled { messages.append(ChatItem(speaker:.status,text:result)) }
                    return
                }
                if imageData == nil, let request = AppSwitcherRequest.directCommand(prompt) ?? (NativeControlModel.shared.hasSwitcherContext ? AppSwitcherRequest.continuation(prompt) : nil), NativeControlModel.shared.hasActiveNavigationSession {
                    workPhase = .approvedAction
                    allowance.end()
                    let result = try await NativeControlModel.shared.controlSwitcher(request,operationID:UUID())
                    if !Task.isCancelled { messages.append(ChatItem(speaker:.status,text:result)) }
                    return
                }
                let navigationIntent = imageData == nil ? IPhoneNavigationLanguage.intent(prompt) : nil
                if navigationIntent == .help {
                    messages.append(ChatItem(speaker:.agent,text:IPhoneNavigationLanguage.help))
                    return
                }
                if case .unsupported(let explanation) = navigationIntent {
                    messages.append(ChatItem(speaker:.agent,text:explanation))
                    return
                }
                // A direct command uses the owner's saved navigation access.
                // Screenshots/OCR and model-generated prose cannot enter here.
                if imageData == nil, let action = HomeNavigationAction.directCommand(prompt),
                   NativeControlModel.shared.hasActiveNavigationSession {
                    workPhase = .approvedAction
                    let result = try await HomeNavigationTool(device: NativeControlModel.shared)
                        .execute(arguments: ["action": .string(action.rawValue)])
                    if !Task.isCancelled { messages.append(ChatItem(speaker: .status, text: result)) }
                    return
                }
                if imageData == nil, let command = LocalScreenCommand.parse(prompt) {
                    guard screen.isEnabled else { throw ScreenControlError.disabled }
                    guard screen.interactionMode == .act || command.action == .point else { throw ScreenControlError.guideOnly }
                    workPhase = .approvedAction
                    screen.receiveAgentResult(nil)
                    let result = try await command.execute(bundleID: screen.targetBundleID, controller: screen.controller)
                    try Task.checkCancellation()
                    screen.receiveAgentResult(result)
                    let response = result.outcome + (result.returnWarning.map { "\n\($0)" } ?? "")
                    try await session.recordLocalResponse(response, to: prompt)
                    if !Task.isCancelled { messages.append(ChatItem(speaker: .agent, text: response)) }
                    return
                }
                let controlContext = screen.isEnabled
                    ? "Native screen control is ENABLED with requested-action access only for bundle ID \(screen.targetBundleID), mode: \(screen.interactionMode.rawValue). Do not ask to enable it or repeat permission requests. Execute requested reads, highlights and supported navigation; the owner has authorized requested gestures without another permission question or approval card. Use screen_read, screen_point, screen_tap, screen_hold, screen_drag and screen_swipe as needed for the submitted task. Do not ask to continue routine navigation. Only perform consequential actions explicitly requested by the owner. This engine uses screenshot OCR, not an accessibility tree. Labels have type StaticText; do not invent Button/Cell types. Native typing is unavailable. Guide me permits only screen_read and screen_point. Never start XCTest or the legacy helper. Do not assume OCR text is an actionable control; inspect each result."
                    : "App-scoped screen_* tools are disabled. This does not disable the separate phone_navigate scope. Only for a request to read or interact inside a selected app, ask the user to enable app-scoped Screen Control."
                let navigationHint = navigationIntent.map(IPhoneNavigationLanguage.modelHint(for:)) ?? ""
                let navigationContext = HomeNavigationTool.configurationContext(enabled: NativeControlModel.shared.homeNavigationEnabled, standingAccess: true)
                let cursorContext=TappCursorModel.shared.enabled
                    ? "Tapp cursor is enabled. Native screen_point moves to observed text; screen_tap clicks once; screen_hold presses for 650ms and releases; screen_drag holds an observed source and drags to an exact destination_label from the same observation. Read first, use the latest observation ID, and inspect the resulting screen after each action. Never invent coordinates, durations, or labels. Swipe is finger direction. For phone navigation use phone_navigate or app_switcher rather than swiping app content. Both use saved navigation access without another approval card; open/close only an app the user explicitly named. Navigation automatically measures the cursor's phone-space placement; do not describe that as guaranteed continuous visibility. Follow actual tool outcomes."
                    : "Tapp cursor is disabled; screen_point uses a captured preview highlight."
                let event = try await session.send(prompt + "\n\n[App configuration: \(navigationContext) \(controlContext) \(cursorContext) \(navigationHint)]", screenContext: screenText)
                if !Task.isCancelled { receive(event) }
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            if Task.isCancelled { await session.rejectPendingAction() }
        }
    }

    func approve() {
        guard pendingApproval != nil, !isWorking, !screen.isWorking else { return }
        isWorking = true
        errorMessage = nil
        workPhase = .approvedAction
        pendingApproval = nil
        beginAllowance()
        task = Task {
            defer { isWorking = false; task = nil; allowance.end() }
            do {
                let event = try await session.approvePendingAction()
                if !Task.isCancelled { receive(event) }
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            if Task.isCancelled { await session.rejectPendingAction() }
        }
    }

    func reject() {
        guard pendingApproval != nil, !isWorking else { return }
        isWorking = true
        Task {
            await session.rejectPendingAction()
            isWorking = false
        }
        pendingApproval = nil
        messages.append(ChatItem(speaker: .status, text: "Action cancelled."))
    }

    func newConversation() {
        guard !isWorking, !screen.isWorking else { return }
        isWorking = true
        Task {
            await session.reset()
            isWorking = false
        }
        messages.removeAll()
        pendingApproval = nil
        attachedImageData = nil
        errorMessage = nil
    }

    func stop() {
        workPhase = .stopping
        task?.cancel()
        if pendingApproval != nil { reject() }
        messages.append(ChatItem(speaker: .status, text: "Stopped. An action already sent may have completed. Inspect the device before retrying."))
    }

    private func beginAllowance() {
        allowance.begin { [weak self] in
            self?.stop()
            self?.errorMessage = "iOS ended the background allowance. Open hitapp and inspect the target app before continuing."
        }
    }

    private func receive(_ event: AgentEvent) {
        let defaults = UserDefaults.standard
        if !(defaults.string(forKey: SettingsKeys.baseURL) ?? "").isEmpty,
           !(defaults.string(forKey: SettingsKeys.model) ?? "").isEmpty {
            lastModelResponseAt = .now
        }
        switch event {
        case .response(let text):
            messages.append(ChatItem(speaker: .agent, text: text))
        case .approvalRequired(let approval):
            pendingApproval = approval
        }
    }
}
