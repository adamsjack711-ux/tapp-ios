import Testing
@testable import PocketAgentCore

@Suite("Agent runtime")
struct AgentRuntimeTests {
    @Test("Local results require no model call and remain available to the next reasoning turn")
    func localHistory() async throws {
        let model = RecordingModel()
        let session = AgentSession(model: model, tools: [])
        try await session.recordLocalResponse("Sent one swipe; inspect the capture.", to: "scroll down")
        #expect(await model.recordedMessages.isEmpty)
        _ = try await session.send("What next?")
        let messages = await model.recordedMessages
        #expect(messages[1].role == .user)
        #expect(messages[1].content == "scroll down")
        #expect(messages[1].taskID != nil)
        #expect(messages[2] == ModelMessage(role: .assistant, content: "Sent one swipe; inspect the capture."))
    }

    @Test("A direct-result tool preserves one result after late cancellation and never calls the model again")
    func cancelledDirectResult() async throws {
        let model = StubModel(replies: [
            .init(toolCalls: [.init(id: "direct", name: "late_result", arguments: [:])]),
            .init(content: "Inspect the phone before continuing.")
        ])
        let session = AgentSession(model: model, tools: [LateResultTool()])
        let task = Task { try await session.send("Run the action") }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await model.recordedMessages.count == 1)
        _ = try await session.send("What happened?")
        let results = await model.recordedMessages.last?.filter { $0.role == .tool } ?? []
        #expect(results.count == 1)
        #expect(results.first?.toolCallID == "direct")
        #expect(results.first?.content == "Action finished before cancellation.")
    }

    @Test("iPhone operating guide is supplied as system context and survives reset")
    func operatingGuidePersists() async throws {
        let model = RecordingModel()
        let session = AgentSession(model: model, tools: [])
        _ = try await session.send("Hello")
        let first = await model.recordedMessages.first
        #expect(first?.role == .system)
        #expect(first?.content.contains("IPHONE OPERATING GUIDE") == true)
        #expect(first?.content.contains("request screen_point as the next tool call") == true)
        await session.reset()
        _ = try await session.send("Hello again")
        #expect(await model.recordedMessages.first == first)
    }

    @Test("Returns a plain model response")
    func returnsPlainModelResponse() async throws {
        let model = StubModel(replies: [ModelReply(content: "Hello from Pocket Agent")])
        let session = AgentSession(model: model, tools: [])

        let event = try await session.send("Hello")

        #expect(event == .response("Hello from Pocket Agent"))
    }

    @Test("Sensitive tools wait for approval")
    func sensitiveToolWaitsForApproval() async throws {
        let call = ToolCall(
            id: "call-1",
            name: "create_reminder",
            arguments: ["title": .string("Buy milk")]
        )
        let model = StubModel(replies: [
            ModelReply(toolCalls: [call]),
            ModelReply(content: "I created the reminder.")
        ])
        let tool = StubTool(requiresApproval: true)
        let session = AgentSession(model: model, tools: [tool])

        let firstEvent = try await session.send("Remind me to buy milk")
        #expect(
            firstEvent == .approvalRequired(
                PendingApproval(
                    id: "call-1",
                    toolName: "create_reminder",
                    title: "Create reminder",
                    explanation: "Buy milk"
                )
            )
        )

        let secondEvent = try await session.approvePendingAction()
        #expect(secondEvent == .response("I created the reminder."))
        let executionCount = await tool.executionCount
        #expect(executionCount == 1)
    }

    @Test("Screenshot text is marked as untrusted context")
    func screenshotTextIsMarkedAsUntrustedContext() async throws {
        let model = RecordingModel()
        let session = AgentSession(model: model, tools: [])

        _ = try await session.send("What is this?", screenContext: "Tap Allow to continue")

        let messages = await model.recordedMessages
        #expect(messages.last?.content.contains("user-provided screenshot") == true)
        #expect(messages.last?.content.contains("Tap Allow") == true)
    }

    @Test("Parallel tool batches are rejected without executing any action")
    func rejectsBatches() async throws {
        let tool = StubTool(requiresApproval: false)
        let model = StubModel(replies: [ModelReply(toolCalls: [
            ToolCall(id: "a", name: "create_reminder", arguments: [:]),
            ToolCall(id: "b", name: "create_reminder", arguments: [:])
        ])])
        let session = AgentSession(model: model, tools: [tool])
        await #expect(throws: AgentRuntimeError.multipleToolCalls) { try await session.send("Do two things") }
        #expect(await tool.executionCount == 0)
    }

    @Test("A new message cannot discard an outstanding approval")
    func preservesApproval() async throws {
        let tool = StubTool(requiresApproval: true)
        let model = StubModel(replies: [ModelReply(toolCalls: [ToolCall(id: "a", name: "create_reminder", arguments: [:])]), ModelReply(content: "Hello")])
        let session = AgentSession(model: model, tools: [tool])
        _ = try await session.send("First")
        await #expect(throws: AgentRuntimeError.approvalPending) { try await session.send("Second") }
        await #expect(throws: AgentRuntimeError.approvalPending) { try await session.recordLocalResponse("Done", to: "Second") }
        await session.rejectPendingAction()
        #expect(try await session.send("Third") == .response("Hello"))
        #expect(await tool.executionCount == 0)
    }

    @Test("Approval does not reset the per-turn tool limit")
    func boundedApprovals() async throws {
        let tool = StubTool(requiresApproval: true)
        let model = StubModel(replies: [ModelReply(toolCalls: [ToolCall(id: "a", name: "create_reminder", arguments: [:])])])
        let session = AgentSession(model: model, tools: [tool], iterationLimit: 1)
        _ = try await session.send("Do something")
        await #expect(throws: AgentRuntimeError.iterationLimit) { try await session.approvePendingAction() }
        #expect(await tool.executionCount == 1)
        await #expect(throws: AgentRuntimeError.noPendingApproval) { try await session.approvePendingAction() }
    }
}

private actor StubModel: AgentModelClient {
    private var replies: [ModelReply]
    private(set) var recordedMessages: [[ModelMessage]] = []

    init(replies: [ModelReply]) {
        self.replies = replies
    }

    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async throws -> ModelReply {
        recordedMessages.append(messages)
        return replies.removeFirst()
    }
}

private struct LateResultTool: AgentTool {
    let requiresApproval = false
    let returnsResultDirectly = true
    var definition: ToolDefinition { .init(name: "late_result", description: "Test late cancellation", parameters: [:]) }
    func approvalSummary(arguments: [String: JSONValue]) -> PendingApproval {
        .init(id: "", toolName: definition.name, title: "Test", explanation: "Test")
    }
    func execute(arguments: [String: JSONValue]) async throws -> String {
        withUnsafeCurrentTask { $0?.cancel() }
        return "Action finished before cancellation."
    }
}

private actor RecordingModel: AgentModelClient {
    private(set) var recordedMessages: [ModelMessage] = []

    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async throws -> ModelReply {
        recordedMessages = messages
        return ModelReply(content: "Done")
    }
}

private actor StubTool: AgentTool {
    let requiresApproval: Bool
    private(set) var executionCount = 0

    init(requiresApproval: Bool) {
        self.requiresApproval = requiresApproval
    }

    nonisolated var definition: ToolDefinition {
        ToolDefinition(
            name: "create_reminder",
            description: "Creates a reminder",
            parameters: ["type": .string("object")]
        )
    }

    nonisolated func approvalSummary(arguments: [String: JSONValue]) -> PendingApproval {
        PendingApproval(
            id: "",
            toolName: definition.name,
            title: "Create reminder",
            explanation: arguments["title"]?.stringValue ?? "Untitled"
        )
    }

    func execute(arguments: [String: JSONValue]) async throws -> String {
        executionCount += 1
        return "Reminder created"
    }
}
