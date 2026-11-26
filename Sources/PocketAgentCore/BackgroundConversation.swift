import Foundation

/// A text-only system-surface conversation. Deliberately has no device/tool executor.
/// Voice capture and confirmation belong to Shortcuts/Siri, not this service.
public actor BackgroundConversation {
    public enum Failure: LocalizedError, Equatable {
        case invalidRequest, busy, timedOut, emptyReply, unexpectedAction
        public var errorDescription: String? {
            switch self {
            case .invalidRequest: return "Please use a request between 1 and 2,000 characters."
            case .busy: return "hitapp is already answering. Please wait for that reply."
            case .timedOut: return "The model didn’t respond in time. Check that your Mac and model connection are available, then try again."
            case .emptyReply: return "The model returned no usable answer. Please try again."
            case .unexpectedAction: return "This voice conversation cannot run phone actions. Nothing was executed; open hitapp yourself to review an action."
            }
        }
    }

    private let model: any AgentModelClient
    private let timeout: Duration
    private var history: [ModelMessage] = []
    private var modelContextID: String?
    private var contextID: String?
    private var busy = false

    public init(model: any AgentModelClient, timeout: Duration = .seconds(25)) {
        self.model = model
        self.timeout = timeout
    }

    public nonisolated static func validate(_ text: String) throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_000 else { throw Failure.invalidRequest }
        return text
    }

    public func answer(_ text: String, contextID: String, now: Date = .now) async throws -> String {
        let question = try Self.validate(text)
        try Task.checkCancellation()
        guard !busy else { throw Failure.busy }
        busy = true
        defer { busy = false }
        // Never carry a conversation across model/provider changes.
        let identity = await model.contextIdentifier()
        if self.contextID != contextID || modelContextID != identity { history = []; self.contextID = contextID }
        modelContextID = identity
        let system = """
        You are hitapp in a compact iPhone system voice interface. Answer conversationally,
        normally in 1–3 short sentences. Do not pretend to be Apple Siri. This surface is text-only:
        no screen access, app launch, taps, swipes, mouse control, reminders, messages, or other actions
        are available. Never claim to have performed, scheduled, saved, or queued an action.
        For a request needing phone control or an app API, briefly explain that it needs review in
        hitapp, which the user must open themselves. Do not promise it will open automatically.
        Do not invent live information: there is no web/API lookup here. No tools are available.
        Current device date/time: \(now.formatted(date: .complete, time: .complete)).
        """
        let user = ModelMessage(role: .user, content: question, taskID: UUID())
        let messages = [ModelMessage(role: .system, content: system)] + history + [user]
        let model = self.model
        let timeout = self.timeout
        let reply = try await withThrowingTaskGroup(of: ModelReply.self) { group in
            defer { group.cancelAll() }
            group.addTask { try await model.reply(to: messages, tools: []) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.timedOut
            }
            guard let reply = try await group.next() else { throw Failure.emptyReply }
            return reply
        }
        try Task.checkCancellation()
        guard await model.contextIdentifier() == identity else { throw AgentRuntimeError.providerChanged }
        guard reply.toolCalls.isEmpty else { throw Failure.unexpectedAction }
        let answer = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, answer.count <= 8_000 else { throw Failure.emptyReply }
        history.append(contentsOf: [user, ModelMessage(role: .assistant, content: answer)])
        history = Array(history.suffix(8)) // Four turns, memory only; no audio or transcript file.
        return answer
    }
}
