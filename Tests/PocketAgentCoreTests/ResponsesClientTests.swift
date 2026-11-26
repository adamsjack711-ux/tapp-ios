import Foundation
import Testing
@testable import PocketAgentCore

@Suite("Tapp Responses integration")
struct ResponsesClientTests {
    static let secret = "tapp_" + String(repeating: "x", count: 43)
    static let answer = #"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done"}]}],"usage":{"input_tokens":120,"output_tokens":35,"input_tokens_details":{"cached_tokens":80},"output_tokens_details":{"reasoning_tokens":30}}}"#
    static let tool = #"{"status":"completed","output":[{"type":"reasoning","id":"rs_1","encrypted_content":"opaque","summary":[]},{"type":"function_call","call_id":"call_1","name":"probe","arguments":"{}"}],"usage":{"input_tokens":100,"output_tokens":10}}"#

    @Test("Swift client reaches the real backend with a mocked provider", .enabled(if: ProcessInfo.processInfo.environment["TAPP_CONTRACT_URL"] != nil))
    func backendHTTPContract() async throws {
        let environment = ProcessInfo.processInfo.environment
        let transport = ContractTransport(base: try #require(environment["TAPP_CONTRACT_URL"]))
        let client = ResponsesModelClient(baseURL: "https://contract.invalid/v1", model: "server",
            accessCode: try #require(environment["TAPP_CONTRACT_TOKEN"]), transport: transport)
        let probe = ResponsesProbe()
        let session = AgentSession(model: client, tools: [probe])
        #expect(try await session.send("Read the probe") == .response("Done"))
        #expect(await probe.calls == 1)
        let accounts = TappAccountClient(baseURL: "https://contract.invalid/v1",
            accessCode: try #require(environment["TAPP_CONTRACT_TOKEN"]), transport: transport)
        let account = try await accounts.account()
        #expect(account.usage.calls == 2)
        #expect(account.usage.chargedTokens == 310)
        #expect(try await accounts.usage().tasks.count == 1)
        let reportID = UUID(), report = TappBugReport(title: "Synthetic bug", description: "Synthetic reproduction steps")
        let receipt = try await accounts.submitBugReport(report, submissionID: reportID)
        #expect(receipt.status == "received")
        #expect(!receipt.duplicate)
        let retry = try await accounts.submitBugReport(report, submissionID: reportID)
        #expect(retry.id == receipt.id)
        #expect(retry.duplicate)
        #expect(try await accounts.account().usage.chargedTokens == 310)
        try await accounts.deleteAccount(confirmedAccountID: account.id)
        await #expect(throws: (any Error).self) { try await accounts.account() }
    }

    @Test("Bug reports use the tester's credentials and retain their submission ID on retry")
    func bugReportWire() async throws {
        let receipt = #"{"id":"report-id","createdAt":1790000000000,"duplicate":false,"status":"received"}"#
        let transport = ResponsesFixture([receipt, receipt], status: 201)
        let client = TappAccountClient(baseURL: "https://beta.example/v1", accessCode: Self.secret, transport: transport)
        let report = TappBugReport(title: "Button stuck", description: "Open Settings, tap Done.")
        let id = UUID()
        #expect(try await client.submitBugReport(report, submissionID: id).status == "received")
        _ = try await client.submitBugReport(report, submissionID: id)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].url?.path == "/v1/bug-reports")
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.secret)")
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Tapp-Request-ID") == id.uuidString })
        let data = try #require(requests[0].httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(body == ["title": report.title, "description": report.description])
    }

    @Test("Bug report failures retain retry timing and unsafe configuration never transmits")
    func bugReportErrors() async throws {
        let report = TappBugReport(title: "Bug", description: "Details")
        let transport = ResponsesFixture([#"{"error":{"code":"bug_report_limit_reached"}}"#], status: 429)
        let client = TappAccountClient(baseURL: "https://beta.example/v1", accessCode: Self.secret, transport: transport)
        do {
            _ = try await client.submitBugReport(report, submissionID: UUID())
            Issue.record("Expected rate limit")
        } catch let error as TappBackendError {
            #expect(error.code == "bug_report_limit_reached")
            #expect(error.retryAfter == 60)
        }
        #expect(await transport.requests.count == 1)
        for (url, code) in [("http://beta.example/v1", Self.secret), ("https://beta.example/v1", "sk-key")] {
            let blocked = ResponsesFixture([])
            let client = TappAccountClient(baseURL: url, accessCode: code, transport: blocked)
            await #expect(throws: (any Error).self) { try await client.submitBugReport(report, submissionID: UUID()) }
            #expect(await blocked.requests.isEmpty)
        }
    }

    @Test("Actual agent round trip preserves encrypted reasoning, call IDs, task ID and usage")
    func roundTrip() async throws {
        let transport = ResponsesFixture([Self.tool, Self.answer])
        let client = ResponsesModelClient(baseURL: "https://beta.example/v1", model: "gpt-6.1-sol", accessCode: Self.secret, transport: transport)
        let probe = ResponsesProbe()
        let session = AgentSession(model: client, tools: [probe])
        #expect(try await session.send("Read the probe") == .response("Done"))
        #expect(await probe.calls == 1)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].url?.path == "/v1/responses")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.secret)")
        #expect(requests[0].value(forHTTPHeaderField: "X-Tapp-Task-ID") == requests[1].value(forHTTPHeaderField: "X-Tapp-Task-ID"))
        #expect(requests[0].value(forHTTPHeaderField: "X-Tapp-Request-ID") != requests[1].value(forHTTPHeaderField: "X-Tapp-Request-ID"))
        let data = try #require(requests[1].httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.contains { $0["encrypted_content"] as? String == "opaque" })
        #expect(input.last?["type"] as? String == "function_call_output")
        #expect(input.last?["call_id"] as? String == "call_1")
        #expect(input.last?["output"] as? String == "Observed result")
        #expect(body["messages"] == nil)
        #expect(body["store"] as? Bool == false)
        let schema = try #require((body["tools"] as? [[String: Any]])?.first)
        #expect(schema["name"] as? String == "probe")
        #expect(schema["function"] == nil)
        let usageClient = ResponsesModelClient(baseURL: "https://beta.example", model: "server", accessCode: Self.secret,
                                               transport: ResponsesFixture([Self.answer]))
        let reply = try await usageClient.reply(to: [ModelMessage(role: .user, content: "Hi")], tools: [])
        #expect(reply.usage == ModelUsage(inputTokens: 120, outputTokens: 35, cachedTokens: 80, reasoningTokens: 30))
    }

    @Test("Incomplete/error responses never execute tools and never retry")
    func incomplete() async throws {
        for status in [200, 502, 429] {
            let data = status == 200 ? #"{"status":"incomplete","output":[{"type":"function_call","call_id":"c","name":"probe","arguments":"{}"}]}"# : #"{"error":{"code":"model_incomplete"}}"#
            let transport = ResponsesFixture([data], status: status), probe = ResponsesProbe()
            let session = AgentSession(model: ResponsesModelClient(baseURL: "https://beta.example/v1", model: "server",
                accessCode: Self.secret, transport: transport), tools: [probe])
            await #expect(throws: (any Error).self) { try await session.send("Run probe") }
            #expect(await probe.calls == 0)
            #expect(await transport.requests.count == 1)
        }
    }

    @Test("Unsafe endpoints and wrong credential types fail before transmission")
    func invalidConfiguration() async throws {
        for (url, code) in [("http://beta.example/v1", Self.secret), ("http://localhost:3000/v1", Self.secret),
                            ("https://user:pass@beta.example/v1", Self.secret), ("https://beta.example/v1?key=x", Self.secret),
                            ("https://beta.example/v1", "sk-provider-key")] {
            let transport = ResponsesFixture([])
            let client = ResponsesModelClient(baseURL: url, model: "server", accessCode: code, transport: transport)
            await #expect(throws: (any Error).self) { try await client.reply(to: [], tools: []) }
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("History is bounded at complete user-turn boundaries")
    func historyBound() async throws {
        let model = ContextProbe()
        let bounded = AgentSession(model: model, tools: [])
        for i in 0..<12 { _ = try await bounded.send("Question \(i)") }
        let last = try #require(await model.received.last)
        #expect(last.filter { $0.role == .user }.count == 3)
        #expect(last.first?.role == .system)
        #expect(last.contains { $0.content == "Question 9" })
        #expect(!last.contains { $0.content == "Question 0" })
    }

    @Test("Changing credentials/provider blocks history transmission until reset")
    func contextGuard() async throws {
        let model = ContextProbe()
        let guarded = AgentSession(model: model, tools: [])
        _ = try await guarded.send("Private first question")
        await model.changeContext()
        await #expect(throws: AgentRuntimeError.providerChanged) { try await guarded.send("Next question") }
        #expect(await model.received.count == 1)
        await guarded.reset()
        _ = try await guarded.send("New conversation")
        let last = try #require(await model.received.last)
        #expect(!last.contains { $0.content == "Private first question" })
    }

    @Test("Credential changes cannot execute a pending approved tool")
    func pendingContextGuard() async throws {
        let model = ContextProbe(), tool = ResponsesProbe(requiresApproval: true)
        await model.proposeTool()
        let session = AgentSession(model: model, tools: [tool])
        guard case .approvalRequired = try await session.send("Run probe") else {
            Issue.record("Expected pending approval"); return
        }
        await model.changeContext()
        await #expect(throws: AgentRuntimeError.providerChanged) { try await session.approvePendingAction() }
        #expect(await tool.calls == 0)
    }

    @Test("Explicit highlight requests send only read and point schemas")
    func narrowTools() async throws {
        let model = ContextProbe()
        let session = AgentSession(model: model, tools: [ResponsesProbe(name: "screen_read"), ResponsesProbe(name: "screen_point"), ResponsesProbe(name: "screen_tap")])
        _ = try await session.send("Show me where General is")
        #expect(await model.toolNames == ["screen_point", "screen_read"])
        _ = try await session.send("Show me General and then tap it")
        #expect(await model.toolNames == ["screen_point", "screen_read", "screen_tap"])
        _ = try await session.send("Highlight General\nTap it next")
        #expect(await model.toolNames == ["screen_point", "screen_read", "screen_tap"])
    }
}

private actor ResponsesFixture: ModelHTTPTransport {
    var responses: [String]
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ responses: [String], status: Int = 200) { self.responses = responses; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let result = responses.isEmpty ? "{}" : responses.removeFirst()
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "60"]))
        return (Data(result.utf8), response)
    }
}

private actor ResponsesProbe: AgentTool {
    nonisolated let requiresApproval: Bool
    nonisolated let definition: ToolDefinition
    private(set) var calls = 0
    init(name: String = "probe", requiresApproval: Bool = false) { self.requiresApproval = requiresApproval; definition = ToolDefinition(name: name, description: "Read synthetic state", parameters: ["type": .string("object")]) }
    nonisolated func approvalSummary(arguments: [String: JSONValue]) -> PendingApproval {
        PendingApproval(id: "", toolName: definition.name, title: "Read", explanation: "Synthetic")
    }
    func execute(arguments: [String: JSONValue]) -> String { calls += 1; return "Observed result" }
}

private actor ContextProbe: AgentModelClient {
    var identity = "first"
    var response = ModelReply(content: "Answer")
    func proposeTool() { response = ModelReply(toolCalls: [ToolCall(id: "p", name: "probe", arguments: [:])]) }
    private(set) var received: [[ModelMessage]] = []
    private(set) var toolNames: [String] = []
    func changeContext() { identity = "second" }
    func contextIdentifier() -> String? { identity }
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) -> ModelReply {
        received.append(messages); toolNames = tools.map(\.name); return response
    }
}

// Test-only URL substitution; production Responses transport requires HTTPS and refuses redirects.
private struct ContractTransport: ModelHTTPTransport {
    let base: String
    private let transport = ModelURLSessionTransport()
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var local = request
        local.url = URL(string: base + (request.url?.path ?? ""))
        return try await transport.send(local)
    }
}
