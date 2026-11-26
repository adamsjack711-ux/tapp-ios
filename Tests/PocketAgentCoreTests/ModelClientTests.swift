import Foundation
import Testing
@testable import PocketAgentCore

@Suite("OpenAI-compatible model client")
struct ModelClientTests {
    @Test("Local Ollama uses no credential and a bounded, single-action request")
    func localRequest() async throws {
        let transport = ModelFixtureTransport()
        let client = OpenAICompatibleClient(baseURL: "http://localhost:11434/v1/", model: "gpt-oss:20b",
                                            apiKey: "cloud-key-must-not-leak", transport: transport)
        #expect(try await client.reply(to: [ModelMessage(role: .user, content: "Hello")], tools: []) == ModelReply(content: "Hello"))
        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try jsonBody(request)
        #expect(body["model"] as? String == "gpt-oss:20b")
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(body["parallel_tool_calls"] as? Bool == false)
        #expect(body["stream"] as? Bool == false)
        #expect(body["max_tokens"] as? Int == 2048)
        #expect(body["tools"] == nil)
    }

    @Test("HTTPS providers require a key before any network request")
    func credentialsRequired() async throws {
        let transport = ModelFixtureTransport()
        let client = OpenAICompatibleClient(baseURL: "https://example.invalid/v1", model: "model", transport: transport)
        await #expect(throws: ModelClientError.missingCredentials) { try await client.reply(to: [], tools: []) }
        #expect(await transport.requests.isEmpty)
    }

    @Test("HTTPS providers receive the key without duplicating the endpoint")
    func remoteRequest() async throws {
        let transport = ModelFixtureTransport()
        let client = OpenAICompatibleClient(baseURL: "https://example.invalid/v1/chat/completions", model: "model",
                                            apiKey: "test-key", transport: transport)
        _ = try await client.reply(to: [], tools: [])
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.url?.path == "/v1/chat/completions")
        #expect(try jsonBody(request)["reasoning_effort"] == nil)
    }

    @Test("Unsafe or credential-bearing URLs fail before network access", arguments: [
        "http://example.invalid/v1", "http://localhost.example.invalid/v1",
        "https://user:password@example.invalid/v1", "https://example.invalid/v1?key=secret",
        "https://example.invalid/v1#fragment", "file:///tmp/model"
    ])
    func unsafeURL(_ baseURL: String) async throws {
        let transport = ModelFixtureTransport()
        let client = OpenAICompatibleClient(baseURL: baseURL, model: "model", apiKey: "test", transport: transport)
        await #expect(throws: ModelClientError.invalidURL) { try await client.reply(to: [], tools: []) }
        #expect(await transport.requests.isEmpty)
    }

    @Test("An empty model is not silently treated as demo mode")
    func emptyModel() async throws {
        let client = OpenAICompatibleClient(baseURL: "http://localhost:11434/v1", model: " ", transport: ModelFixtureTransport())
        await #expect(throws: ModelClientError.invalidConfiguration) { try await client.reply(to: [], tools: []) }
    }

    @Test("Tool context and call IDs survive the actual agent loop")
    func toolRoundTrip() async throws {
        let transport = ModelFixtureTransport(responses: [Self.toolResponse, ModelFixtureTransport.greeting])
        let client = OpenAICompatibleClient(baseURL: "http://127.0.0.1:11434/v1", model: "gpt-oss:20b", transport: transport)
        let tool = ModelProbeTool()
        let session = AgentSession(model: client, tools: [tool])
        #expect(try await session.send("Read the time") == .response("Hello"))
        #expect(await tool.executionCount == 1)
        let requests = await transport.requests
        #expect(requests.count == 2)
        let messages = try #require(try jsonBody(requests[1])["messages"] as? [[String: Any]])
        let assistant = try #require(messages.first { $0["role"] as? String == "assistant" })
        #expect(assistant["reasoning"] as? String == "opaque-provider-context")
        let result = try #require(messages.last)
        #expect(result["role"] as? String == "tool")
        #expect(result["tool_call_id"] as? String == "call-1")
        #expect(result["content"] as? String == tool.result)
    }

    @Test("Final-answer reasoning is never returned for display")
    func finalReasoning() async throws {
        let transport = ModelFixtureTransport(responses: [#"{"choices":[{"message":{"content":"Final answer","reasoning":"not a user-facing answer"}}]}"#])
        let client = OpenAICompatibleClient(baseURL: "http://localhost:11434/v1", model: "gpt-oss:20b", transport: transport)
        #expect(try await client.reply(to: [], tools: []) == ModelReply(content: "Final answer"))
    }

    @Test("Alternate reasoning field is accepted for tool responses")
    func alternativeReasoningField() async throws {
        let transport = ModelFixtureTransport(responses: [Self.toolResponse.replacingOccurrences(of: "\"reasoning\"", with: "\"reasoning_content\"")])
        let client = OpenAICompatibleClient(baseURL: "http://localhost:11434/v1", model: "gpt-oss:20b", transport: transport)
        #expect(try await client.reply(to: [], tools: []).reasoningContent == "opaque-provider-context")
    }

    @Test("Invalid function calls fail closed", arguments: [
        #"{"choices":[{"message":{"tool_calls":[{"id":"","type":"function","function":{"name":"current_time","arguments":"{}"}}]}}]}"#,
        #"{"choices":[{"message":{"tool_calls":[{"id":"call","type":"function","function":{"name":"current_time","arguments":"not JSON"}}]}}]}"#,
        #"{"choices":[]}"#
    ])
    func malformedResponse(_ response: String) async throws {
        let client = OpenAICompatibleClient(baseURL: "http://localhost:11434/v1", model: "gpt-oss:20b",
                                            transport: ModelFixtureTransport(responses: [response]))
        await #expect(throws: (any Error).self) { try await client.reply(to: [], tools: []) }
    }

    @Test("Provider failures are surfaced without retrying")
    func noRetries() async throws {
        let transport = ModelFixtureTransport(responses: [#"{"error":{"message":"model is missing"}}"#], status: 404)
        let client = OpenAICompatibleClient(baseURL: "http://localhost:11434/v1", model: "gpt-oss:20b", transport: transport)
        await #expect(throws: ModelClientError.provider(status: 404, detail: "model is missing")) {
            try await client.reply(to: [], tools: [])
        }
        #expect(await transport.requests.count == 1)
    }

    private static let toolResponse = #"{"choices":[{"message":{"content":null,"reasoning":"opaque-provider-context","tool_calls":[{"id":"call-1","type":"function","function":{"name":"current_time","arguments":"{}"}}]}}]}"#
}

@Suite("Live local Ollama", .serialized)
struct LiveOllamaTests {
    @Test("iPhone guide requests an observed highlight after a screen read", .enabled(if: ProcessInfo.processInfo.environment["POCKET_AGENT_LIVE_OLLAMA"] == "1"))
    func liveObservedHighlight() async throws {
        // Synthetic UI only: this test never contacts or controls an iPhone.
        let controller = ScreenController(rpc: NoPhoneRPC(), returnBundleID: "test.pocketagent")
        let definitions = ScreenAction.allCases.map { ScreenTool(action: $0, controller: controller).definition }
        let observation = "observation-" + UUID().uuidString
        let reply = try await client.reply(to: [
            ModelMessage(role: .system, content: AgentSession.defaultSystemPrompt),
            ModelMessage(role: .user, content: "Show me General in Settings with a highlight. Guide me is enabled only for com.apple.Preferences."),
            ModelMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: "read-1", name: "screen_read", arguments: ["bundle_id": .string("com.apple.Preferences")])]),
            ModelMessage(role: .tool, content: "Approved screen read completed. bundle_id=com.apple.Preferences; observation_id=\(observation); captured just now. Visible tree: Button label=General, identifier=General, frame=(20,600,360,52). No system alert. Returned to Pocket Agent. No highlight has been performed.", toolCallID: "read-1")
        ], tools: definitions)
        #expect(reply.toolCalls.count == 1)
        let call = try #require(reply.toolCalls.first)
        #expect(call.name == "screen_point")
        #expect(call.arguments["label"] == .string("General"))
        #expect(call.arguments["bundle_id"] == .string("com.apple.Preferences"))
        #expect(call.arguments["observation_id"] == .string(observation))
        #expect(call.arguments["element_type"] == nil || call.arguments["element_type"] == .string("Button"))
    }

    private var client: OpenAICompatibleClient {
        OpenAICompatibleClient(baseURL: "http://localhost:11434/v1", model: "gpt-oss:20b")
    }

    @Test("gpt-oss:20b gives a live answer", .enabled(if: ProcessInfo.processInfo.environment["POCKET_AGENT_LIVE_OLLAMA"] == "1"))
    func liveAnswer() async throws {
        let reply = try await client.reply(to: [ModelMessage(role: .user, content: "Reply with exactly LOCAL_OK and nothing else.")], tools: [])
        #expect(reply.content.contains("LOCAL_OK"))
        #expect(reply.toolCalls.isEmpty)
        print("Live Ollama answer: \(reply.content)")
    }

    @Test("gpt-oss:20b calls a Swift tool and uses its result", .enabled(if: ProcessInfo.processInfo.environment["POCKET_AGENT_LIVE_OLLAMA"] == "1"))
    func liveToolRoundTrip() async throws {
        let tool = ModelProbeTool()
        let session = AgentSession(model: client, tools: [tool])
        let event = try await session.send("Call current_time exactly once. Then repeat the verification code from its result exactly. Do not guess the code.")
        #expect(await tool.executionCount == 1)
        guard case .response(let answer) = event else {
            Issue.record("Expected a final answer after the read-only tool"); return
        }
        #expect(answer.contains(tool.verificationCode))
        print("Live Ollama tool round-trip: 1 Swift execution; result code present in answer.")
    }

    @Test("A live model request cannot bypass approval", .enabled(if: ProcessInfo.processInfo.environment["POCKET_AGENT_LIVE_OLLAMA"] == "1"))
    func liveApprovalBoundary() async throws {
        let tool = ModelProbeTool(requiresApproval: true)
        let session = AgentSession(model: client, tools: [tool])
        let event = try await session.send("Use current_time to read the clock now. Request that tool exactly once.")
        guard case .approvalRequired(let approval) = event else {
            Issue.record("Expected an approval request"); return
        }
        #expect(approval.toolName == "current_time")
        #expect(await tool.executionCount == 0)
        await session.rejectPendingAction()
        #expect(await tool.executionCount == 0)
        print("Live Ollama approval boundary: requested, declined, zero tool executions.")
    }
}

private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private struct NoPhoneRPC: ScreenRPC {
    func call(_ method: String, parameters: [String: JSONValue]) async throws -> [String: JSONValue] {
        throw ICTRLError.invalidResponse
    }
}

private actor ModelFixtureTransport: ModelHTTPTransport {
    static let greeting = #"{"choices":[{"message":{"content":"Hello"}}]}"#
    private var responses: [String]
    private let status: Int
    private(set) var requests: [URLRequest] = []
    init(responses: [String] = [greeting], status: Int = 200) {
        self.responses = responses
        self.status = status
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let data = Data(responses.removeFirst().utf8)
        let url = try #require(request.url)
        return (data, try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)))
    }
}

private actor ModelProbeTool: AgentTool {
    let requiresApproval: Bool
    let verificationCode = "POCKET_" + UUID().uuidString
    nonisolated var result: String { "Test clock time: 2026-10-18T13:30:00-07:00. Verification code: \(verificationCode)" }
    private(set) var executionCount = 0
    init(requiresApproval: Bool = false) { self.requiresApproval = requiresApproval }
    nonisolated var definition: ToolDefinition {
        ToolDefinition(name: "current_time", description: "Returns the clock time and a verification code for this local test.",
                       parameters: ["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)])
    }
    nonisolated func approvalSummary(arguments: [String: JSONValue]) -> PendingApproval {
        PendingApproval(id: "", toolName: "current_time", title: "Read test clock", explanation: "A harmless in-memory test; no external changes.")
    }
    func execute(arguments: [String: JSONValue]) async throws -> String {
        executionCount += 1
        return result
    }
}
