import Foundation

public protocol ModelHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct ModelURLSessionTransport: ModelHTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration, delegate: NoModelRedirects(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ModelClientError.invalidResponse }
        return (data, response)
    }
}

private final class NoModelRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ModelClientError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidURL
    case missingCredentials
    case invalidResponse
    case provider(status: Int, detail: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Enter both a model URL and model name, or clear both to use demo mode."
        case .invalidURL: return "Use an HTTPS provider URL, or HTTP localhost for Ollama in the simulator."
        case .missingCredentials: return "Add your model provider's API key in Settings. Local Ollama needs no key."
        case .invalidResponse: return "The model provider returned an unreadable response."
        case .provider(let status, let detail): return "Provider error \(status): \(detail)"
        }
    }
}

/// Shared by the iOS app and tests so the live integration uses the tested wire format.
public struct OpenAICompatibleClient: AgentModelClient {
    public let baseURL: String
    public let model: String
    private let apiKey: String
    private let transport: any ModelHTTPTransport

    public init(baseURL: String, model: String, apiKey: String = "",
                transport: any ModelHTTPTransport = ModelURLSessionTransport()) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.transport = transport
    }

    public static func isLoopback(_ url: URL) -> Bool {
        ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host?.lowercased() ?? "")
    }

    public func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async throws -> ModelReply {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelClientError.invalidConfiguration }
        guard let url = endpointURL else { throw ModelClientError.invalidURL }
        let local = Self.isLoopback(url)
        guard local || !apiKey.isEmpty else { throw ModelClientError.missingCredentials }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Never forward an existing cloud-provider credential to the local Ollama service.
        if !local { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model, messages: try messages.map(APIMessage.init),
            tools: tools.isEmpty ? nil : tools.map(APITool.init),
            reasoningEffort: model.hasPrefix("gpt-oss") ? "low" : nil
        ))
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message)
                ?? "The provider rejected the request. Check its address and model name."
            throw ModelClientError.provider(status: response.statusCode, detail: String(detail.prefix(500)))
        }
        let payload = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let message = payload.choices.first?.message else { throw ModelClientError.invalidResponse }
        let calls: [ToolCall] = try message.toolCalls?.map { call in
            guard call.type == "function", !call.id.isEmpty else { throw ModelClientError.invalidResponse }
            return ToolCall(id: call.id, name: call.function.name,
                            arguments: try JSONDecoder().decode([String: JSONValue].self,
                                                               from: Data(call.function.arguments.utf8)))
        } ?? []
        return ModelReply(content: message.content ?? "", toolCalls: calls,
                          reasoningContent: calls.isEmpty ? nil : message.reasoningContent)
    }

    private var endpointURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let original = components.url,
              components.scheme == "https" || (components.scheme == "http" && Self.isLoopback(original)) else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        components.path = path
        return components.url
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [APIMessage]
    let tools: [APITool]?
    let reasoningEffort: String?
    let stream = false
    let parallelToolCalls = false
    let maxTokens = 2048

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream
        case reasoningEffort = "reasoning_effort"
        case parallelToolCalls = "parallel_tool_calls"
        case maxTokens = "max_tokens"
    }
}

private struct APIMessage: Encodable {
    let role: String
    let content: String?
    let toolCallID: String?
    let toolCalls: [APIToolCall]?
    let reasoningContent: String?

    init(_ message: ModelMessage) throws {
        role = message.role.rawValue
        content = message.content.isEmpty && !message.toolCalls.isEmpty ? nil : message.content
        toolCallID = message.toolCallID
        toolCalls = message.toolCalls.isEmpty ? nil : try message.toolCalls.map(APIToolCall.init)
        reasoningContent = message.role == .assistant && !message.toolCalls.isEmpty ? message.reasoningContent : nil
    }
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
        case reasoningContent = "reasoning"
    }
}

private struct APITool: Encodable {
    let type = "function"
    let function: ToolDefinition
    init(_ definition: ToolDefinition) { function = definition }
}

private struct APIToolCall: Codable {
    let id: String
    let type: String
    let function: Function
    struct Function: Codable { let name: String; let arguments: String }
    init(_ call: ToolCall) throws {
        id = call.id
        type = "function"
        function = Function(name: call.name, arguments: String(decoding: try JSONEncoder().encode(call.arguments), as: UTF8.self))
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let message: ResponseMessage }
    struct ResponseMessage: Decodable {
        let content: String?
        let toolCalls: [APIToolCall]?
        let reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content, reasoning
            case toolCalls = "tool_calls"
            case reasoningContent = "reasoning_content"
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            content = try values.decodeIfPresent(String.self, forKey: .content)
            toolCalls = try values.decodeIfPresent([APIToolCall].self, forKey: .toolCalls)
            reasoningContent = try values.decodeIfPresent(String.self, forKey: .reasoning)
                ?? values.decodeIfPresent(String.self, forKey: .reasoningContent)
        }
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError
    struct APIError: Decodable { let message: String }
}

/// Stateless Responses transport used by Tapp beta and direct OpenAI connections.
/// Tool execution remains in AgentSession and retains all local approval checks.
public struct ResponsesModelClient: AgentModelClient {
    public let baseURL: String
    public let model: String
    private let accessCode: String
    private let isTappBackend: Bool
    private let transport: any ModelHTTPTransport

    public init(baseURL: String, model: String, accessCode: String, isTappBackend: Bool = true,
                transport: any ModelHTTPTransport = ModelURLSessionTransport()) {
        self.baseURL = baseURL
        self.model = model
        self.accessCode = accessCode
        self.isTappBackend = isTappBackend
        self.transport = transport
    }

    public static func endpoint(baseURL: String) -> URL? {
        guard var parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.scheme == "https" else { return nil }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        if parts.path.isEmpty { parts.path = "/v1" }
        if parts.path.hasSuffix("/chat/completions") { parts.path.removeLast("/chat/completions".count) }
        if !parts.path.hasSuffix("/responses") { parts.path += "/responses" }
        return parts.url
    }

    public func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async throws -> ModelReply {
        guard let url = Self.endpoint(baseURL: baseURL) else { throw ModelClientError.invalidURL }
        guard !accessCode.isEmpty else { throw ModelClientError.missingCredentials }
        if isTappBackend {
            guard accessCode.range(of: "^tapp_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
                throw ModelClientError.missingCredentials
            }
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessCode)", forHTTPHeaderField: "Authorization")
        if isTappBackend {
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Tapp-Request-ID")
            request.setValue((messages.last(where: { $0.role == .user })?.taskID ?? UUID()).uuidString,
                             forHTTPHeaderField: "X-Tapp-Task-ID")
        }
        request.httpBody = try encodeInput(messages, tools: tools)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            if isTappBackend {
                let body = try? JSONDecoder().decode(BackendFailure.self, from: data)
                throw TappBackendError(status: response.statusCode, code: body?.error.code ?? "service_unavailable",
                                       retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
            }
            throw ModelClientError.provider(status: response.statusCode, detail: "The Responses request failed. No automatic retry was made.")
        }
        return try Self.decode(data)
    }

    private func encodeInput(_ messages: [ModelMessage], tools: [ToolDefinition]) throws -> Data {
        var input: [JSONValue] = []
        for message in messages {
            if message.role == .assistant, let items = message.responseItems, !items.isEmpty {
                input.append(contentsOf: items)
            } else if message.role == .tool {
                guard let id = message.toolCallID, !id.isEmpty else { throw ModelClientError.invalidResponse }
                input.append(.object(["type": .string("function_call_output"), "call_id": .string(id), "output": .string(message.content)]))
            } else {
                if !message.content.isEmpty {
                    input.append(.object(["role": .string(message.role.rawValue), "content": .string(message.content)]))
                }
                for call in message.toolCalls {
                    input.append(.object(["type": .string("function_call"), "call_id": .string(call.id), "name": .string(call.name),
                        "arguments": .string(String(decoding: try JSONEncoder().encode(call.arguments), as: UTF8.self))]))
                }
            }
        }
        let functions = tools.map { definition in JSONValue.object([
            "type": .string("function"), "name": .string(definition.name), "description": .string(definition.description),
            "parameters": .object(definition.parameters), "strict": .bool(false)
        ]) }
        let body: JSONValue = .object(["model": .string(model), "input": .array(input), "tools": .array(functions),
            "store": .bool(false), "stream": .bool(false), "parallel_tool_calls": .bool(false),
            "max_output_tokens": .number(4096), "reasoning": .object(["effort": .string("low")]),
            "include": .array([.string("reasoning.encrypted_content")])])
        let data = try JSONEncoder().encode(body)
        guard input.count <= 80, data.count <= 2 * 1024 * 1024 else {
            throw TappBackendError(status: 413, code: "request_too_large", retryAfter: nil)
        }
        return data
    }

    private static func decode(_ data: Data) throws -> ModelReply {
        guard data.count <= 4 * 1024 * 1024,
              case .object(let body) = try JSONDecoder().decode(JSONValue.self, from: data),
              body["status"] == .string("completed"), case .array(let items) = body["output"] else {
            throw ModelClientError.invalidResponse
        }
        var text: [String] = [], calls: [ToolCall] = []
        for item in items {
            guard case .object(let value) = item else { throw ModelClientError.invalidResponse }
            switch value["type"]?.stringValue {
            case "message":
                guard value["role"] == .string("assistant"), case .array(let content) = value["content"] else {
                    throw ModelClientError.invalidResponse
                }
                for part in content {
                    guard case .object(let field) = part else { throw ModelClientError.invalidResponse }
                    if field["type"] == .string("output_text"), let answer = field["text"]?.stringValue { text.append(answer) }
                    else if field["type"] == .string("refusal"), let refusal = field["refusal"]?.stringValue { text.append(refusal) }
                    else { throw ModelClientError.invalidResponse }
                }
            case "function_call":
                guard let id = value["call_id"]?.stringValue, !id.isEmpty,
                      !calls.contains(where: { $0.id == id }), let name = value["name"]?.stringValue, !name.isEmpty,
                      let arguments = value["arguments"]?.stringValue else { throw ModelClientError.invalidResponse }
                calls.append(ToolCall(id: id, name: name, arguments: try JSONDecoder().decode([String: JSONValue].self, from: Data(arguments.utf8))))
            case "reasoning":
                guard let opaque = value["encrypted_content"]?.stringValue, !opaque.isEmpty,
                      let id = value["id"]?.stringValue, !id.isEmpty else { throw ModelClientError.invalidResponse }
            default: throw ModelClientError.invalidResponse
            }
        }
        let usage: ModelUsage?
        if case .object(let value) = body["usage"],
           let input = tokenCount(value["input_tokens"]), let output = tokenCount(value["output_tokens"]) {
            var cached: Int?, reasoning: Int?
            if case .object(let details) = value["input_tokens_details"] { cached = tokenCount(details["cached_tokens"]) }
            if case .object(let details) = value["output_tokens_details"] { reasoning = tokenCount(details["reasoning_tokens"]) }
            usage = ModelUsage(inputTokens: input, outputTokens: output,
                               cachedTokens: cached.flatMap { $0 <= input ? $0 : nil },
                               reasoningTokens: reasoning.flatMap { $0 <= output ? $0 : nil })
        } else { usage = nil }
        return ModelReply(content: text.joined(separator: "\n"), toolCalls: calls, responseItems: items, usage: usage)
    }

    private static func tokenCount(_ value: JSONValue?) -> Int? {
        guard let n = value?.numberValue, n.isFinite, n >= 0, n <= 9_007_199_254_740_991, n.rounded() == n else { return nil }
        return Int(n)
    }
}

public struct TappBackendError: LocalizedError, Equatable, Sendable {
    public let status: Int
    public let code: String
    public let retryAfter: Int?
    public var errorDescription: String? {
        switch code {
        case "invalid_access_code": return "Your Tapp beta access code is invalid, expired or revoked."
        case "token_limit_reached", "daily_limit_reached": return "Your Tapp daily allowance is used or too small for this request. It resets at midnight UTC."
        case "request_already_attempted": return "This request was already attempted. Check the phone before starting another action."
        case "request_in_progress": return "Tapp is still processing a request. Wait for it to finish."
        case "model_incomplete": return "The model could not finish this step. Some tokens may have been used; no action from this response was executed."
        case "request_too_large": return "This conversation is too large. Start a new conversation."
        case "invalid_bug_report": return "Check your report's title and description and try again."
        case "bug_report_limit_reached": return "You’ve sent 10 bug reports today. You can send more after midnight UTC."
        case "bug_report_id_conflict": return "This report was already sent with different details. Close this form to start a new report."
        default: return "Tapp could not complete the request (\(status)). No automatic retry was made."
        }
    }
}

private struct BackendFailure: Decodable {
    let error: Failure
    struct Failure: Decodable { let code: String }
}

/// Authenticated beta account operations and explicitly submitted bug reports.
public struct TappAccountClient: Sendable {
    private let baseURL: String
    private let accessCode: String
    private let transport: any ModelHTTPTransport
    public init(baseURL: String, accessCode: String, transport: any ModelHTTPTransport = ModelURLSessionTransport()) {
        self.baseURL = baseURL; self.accessCode = accessCode; self.transport = transport
    }
    public func account() async throws -> TappAccount {
        try JSONDecoder().decode(TappAccount.self, from: await request(path: "account"))
    }
    public func usage() async throws -> TappUsageReport {
        try JSONDecoder().decode(TappUsageReport.self, from: await request(path: "usage"))
    }
    public func deleteAccount(confirmedAccountID: String) async throws {
        guard UUID(uuidString: confirmedAccountID) != nil else { throw ModelClientError.invalidConfiguration }
        _ = try await request(path: "account", method: "DELETE", confirmation: confirmedAccountID)
    }
    /// Keep submissionID and report unchanged when retrying an uncertain network result.
    public func submitBugReport(_ report: TappBugReport, submissionID: UUID) async throws -> TappBugReportReceipt {
        try JSONDecoder().decode(TappBugReportReceipt.self, from: await request(path: "bug-reports", method: "POST",
            body: JSONEncoder().encode(report), submissionID: submissionID))
    }
    private func request(path: String, method: String = "GET", confirmation: String? = nil,
                         body: Data? = nil, submissionID: UUID? = nil) async throws -> Data {
        guard let endpoint = ResponsesModelClient.endpoint(baseURL: baseURL) else { throw ModelClientError.invalidURL }
        guard accessCode.range(of: "^tapp_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw ModelClientError.missingCredentials
        }
        var request = URLRequest(url: endpoint.deletingLastPathComponent().appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("Bearer \(accessCode)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let submissionID { request.setValue(submissionID.uuidString, forHTTPHeaderField: "X-Tapp-Request-ID") }
        if let confirmation { request.setValue(confirmation, forHTTPHeaderField: "X-Tapp-Confirm-Delete") }
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(BackendFailure.self, from: data)
            throw TappBackendError(status: response.statusCode, code: error?.error.code ?? "service_unavailable",
                                   retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        }
        return data
    }
}

public struct TappBugReport: Codable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var appVersion: String?
    public var osVersion: String?
    public var deviceModel: String?

    public init(title: String, description: String, appVersion: String? = nil,
                osVersion: String? = nil, deviceModel: String? = nil) {
        self.title = title; self.description = description; self.appVersion = appVersion
        self.osVersion = osVersion; self.deviceModel = deviceModel
    }
}

public struct TappBugReportReceipt: Decodable, Equatable, Sendable {
    public let id: String
    public let createdAt: Int64
    public let duplicate: Bool
    public let status: String
}

public struct TappAccount: Decodable, Equatable, Sendable {
    public let id: String
    public let plan: String
    /// Server timestamps are milliseconds since Unix epoch.
    public let expiresAt: Int64
    public let dailyLimit: Int
    public let requestsToday: Int
    public let model: String
    public let tokenLimit: Int
    public let tokensRemaining: Int
    public let usage: TappUsageSummary
}
public struct TappUsageSummary: Decodable, Equatable, Sendable {
    public let calls: Int
    public let tasks: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int
    public let reasoningTokens: Int
    public let chargedTokens: Int
    public let unsettledCalls: Int
    public let unknownUsageCalls: Int
    public let unknownBreakdownCalls: Int
    public let resetsAt: Int64
}
public struct TappUsageReport: Decodable, Equatable, Sendable {
    public let usage: TappUsageSummary
    public let tasks: [TappTaskUsage]
}
public struct TappTaskUsage: Decodable, Equatable, Sendable {
    public let taskID: String
    public let calls: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int
    public let reasoningTokens: Int
    public let chargedTokens: Int
    public let durationMS: Int?
    public let unknownUsageCalls: Int
    public let failedOrPendingCalls: Int
    public let startedAt: Int64
}
