import Foundation
import Testing
@testable import PocketAgentCore

@Suite("Background voice conversation")
struct BackgroundConversationTests {
    @Test("Live configured Mac model answers a text-only background request", .enabled(if: ProcessInfo.processInfo.environment["POCKET_AGENT_LIVE_HOME_WIFI"] == "1"))
    func liveAnswer() async throws {
        let keyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PocketAgent/model-gateway.key")
        let key = try String(contentsOf: keyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let model = OpenAICompatibleClient(baseURL: "https://\(HomeWiFiModelTransport.serverName)/v1", model: "gpt-oss:20b", apiKey: key, transport: HomeWiFiModelTransport())
        let conversation = BackgroundConversation(model: model)
        let answer = try await conversation.answer("Briefly say hello. Can you see or control my phone from this voice conversation?", contextID: "live-test")
        #expect(!answer.isEmpty)
        #expect(answer.count < 2_000)
    }

    @Test("Validates before contacting the model")
    func validation() async throws {
        let model = VoiceModel()
        let conversation = BackgroundConversation(model: model)
        for input in [" \n", String(repeating: "x", count: 2_001)] {
            await #expect(throws: BackgroundConversation.Failure.invalidRequest) {
                try await conversation.answer(input, contextID: "test")
            }
        }
        #expect(await model.requests.isEmpty)
        #expect(try BackgroundConversation.validate("  hello \n") == "hello")
    }

    @Test("Uses no tools, keeps four turns, and clears history on provider changes")
    func history() async throws {
        let model = VoiceModel()
        let conversation = BackgroundConversation(model: model)
        for index in 0..<6 { _ = try await conversation.answer("question \(index)", contextID: "first") }
        let requests = await model.requests
        #expect(requests.allSatisfy { $0.tools.isEmpty })
        #expect(requests.last?.messages.count == 10) // system + 4 pairs + current request
        #expect(requests.last?.messages[1].content == "question 1")
        #expect(requests[0].messages[0].content.contains("no screen access"))
        _ = try await conversation.answer("new provider", contextID: "second")
        #expect(await model.requests.last?.messages.count == 2)
    }

    @Test("Unexpected model tool calls never execute and never enter history")
    func toolsRejected() async throws {
        let model = VoiceModel(replies: [ModelReply(toolCalls: [.init(id: "1", name: "phone_navigate", arguments: [:])]), .init(content: "hello")])
        let conversation = BackgroundConversation(model: model)
        await #expect(throws: BackgroundConversation.Failure.unexpectedAction) { try await conversation.answer("Go Home", contextID: "test") }
        _ = try await conversation.answer("hello", contextID: "test")
        #expect(await model.requests.last?.messages.count == 2)
    }

    @Test("Empty and oversized answers fail without committing history")
    func emptyAnswer() async throws {
        for reply in [" \n", String(repeating: "x", count: 8_001)] {
            let conversation = BackgroundConversation(model: VoiceModel(replies: [.init(content: reply)]))
            await #expect(throws: BackgroundConversation.Failure.emptyReply) { try await conversation.answer("hello", contextID: "test") }
        }
    }

    @Test("Timeout is bounded and cancels a waiting transport")
    func timeout() async throws {
        let conversation = BackgroundConversation(model: SlowVoiceModel(), timeout: .milliseconds(10))
        await #expect(throws: BackgroundConversation.Failure.timedOut) { try await conversation.answer("hello", contextID: "test") }
    }

    @Test("Overlapping requests are rejected and cancellation releases the busy state")
    func cancellation() async throws {
        let model = SlowVoiceModel()
        let conversation = BackgroundConversation(model: model)
        let first = Task { try await conversation.answer("first", contextID: "test") }
        await model.waitUntilStarted()
        await #expect(throws: BackgroundConversation.Failure.busy) { try await conversation.answer("second", contextID: "test") }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        let third = Task { try await conversation.answer("third", contextID: "test") }
        await model.waitForRequests(2)
        third.cancel()
        await #expect(throws: CancellationError.self) { try await third.value }
        #expect(await model.lastMessages.count == 2)
    }
}

private actor VoiceModel: AgentModelClient {
    struct Request: Sendable { let messages: [ModelMessage]; let tools: [ToolDefinition] }
    var requests: [Request] = []
    var replies: [ModelReply]
    init(replies: [ModelReply] = []) { self.replies = replies }
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) -> ModelReply {
        requests.append(.init(messages: messages, tools: tools))
        return replies.isEmpty ? .init(content: "A short answer.") : replies.removeFirst()
    }
}

private actor SlowVoiceModel: AgentModelClient {
    var count = 0
    var lastMessages: [ModelMessage] = []
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async throws -> ModelReply {
        count += 1; lastMessages = messages
        try await Task.sleep(for: .seconds(60))
        return .init(content: "late")
    }
    func waitUntilStarted() async { await waitForRequests(1) }
    func waitForRequests(_ expected: Int) async { while count < expected { await Task.yield() } }
}
