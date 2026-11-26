import AppIntents
import Combine
import Foundation
import SwiftUI

/// Only the explicitly named Open action can request the app's composer.
@MainActor
final class AgentLaunchCoordinator: ObservableObject {
    static let shared = AgentLaunchCoordinator()
    private static let pendingKey = "shortcut.pendingCompose"
    @Published private(set) var composeRequestID: String?

    private init() {
        // Migration: an older Action-button invocation must never start our microphone later.
        UserDefaults.standard.removeObject(forKey: "shortcut.pendingDictation")
        UserDefaults.standard.removeObject(forKey: "shortcut.requestedAt")
        composeRequestID = UserDefaults.standard.string(forKey: Self.pendingKey)
    }

    func requestComposer() {
        let identifier = UUID().uuidString
        UserDefaults.standard.set(identifier, forKey: Self.pendingKey)
        composeRequestID = identifier
    }

    func consumeComposeRequest() -> Bool {
        guard composeRequestID != nil || UserDefaults.standard.string(forKey: Self.pendingKey) != nil else { return false }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        composeRequestID = nil
        return true
    }
}

struct SummonPocketAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Open hitapp"
    static var description = IntentDescription("Opens the message composer, ready for your next request. Does not record or send automatically.")
    static var openAppWhenRun = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        AgentLaunchCoordinator.shared.requestComposer()
        return .result()
    }
}

struct PocketAgentShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DictatePocketAgentIntent(),
                    phrases: ["Ask \(.applicationName)", "Dictate to \(.applicationName)"],
                    shortTitle: "Ask hitapp", systemImageName: "mic")
        AppShortcut(
            intent: SummonPocketAgentIntent(),
            phrases: [
                "Open \(.applicationName)"
            ],
            shortTitle: "Open hitapp",
            systemImageName: "sparkles"
        )
    }
}

struct DictatePocketAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Dictate to hitapp"
    static var description = IntentDescription("Answers in the system interface without opening hitapp. In a shortcut, put Dictate Text before this action and pass its text as Request. Review before sending to your configured model. Conversation only; no phone actions.")
    static var openAppWhenRun = false
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(title: "Request", requestValueDialog: "What would you like to ask hitapp?",
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var request: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask hitapp \(\.$request)")
    }

    private static let conversation = BackgroundConversation(model: ConfiguredModelClient())

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let question = try BackgroundConversation.validate(request)
        let confirmation: IntentDialog = "Send ‘\(question)’ to hitapp’s configured model? Text only; no phone actions."
        if #available(iOS 18.0, *) {
            try await requestConfirmation(dialog: confirmation)
        } else {
            throw VoiceSurfaceError.requiresNewerSystem
        }
        try Task.checkCancellation()
        let defaults = UserDefaults.standard
        let context = (defaults.string(forKey: SettingsKeys.baseURL) ?? "") + "|" + (defaults.string(forKey: SettingsKeys.model) ?? "")
        let answer = try await Self.conversation.answer(question, contextID: context)
        return .result(value: answer, dialog: "\(answer)", view:
            VStack(alignment: .leading, spacing: 10) {
                Label("hitapp", systemImage: "sparkles").font(.headline)
                Text(answer)
                Text("Voice conversation · no phone action was run").font(.caption).foregroundStyle(.secondary)
            }.padding()
        )
    }
}

private enum VoiceSurfaceError: LocalizedError {
    case requiresNewerSystem
    var errorDescription: String? { "This system voice conversation requires iOS 18 or newer. The in-app microphone is still available; the app will not open automatically." }
}
