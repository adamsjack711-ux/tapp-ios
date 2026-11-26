import Foundation

public struct ToolDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let parameters: [String: JSONValue]

    public init(name: String, description: String, parameters: [String: JSONValue]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ToolCall: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let arguments: [String: JSONValue]

    public init(id: String, name: String, arguments: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct ModelMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant, tool
    }

    public let role: Role
    public let content: String
    public let toolCallID: String?
    public let toolCalls: [ToolCall]
    /// Provider context for a tool round-trip; never displayed as the assistant's answer.
    public let reasoningContent: String?
    public let responseItems: [JSONValue]?
    public let taskID: UUID?

    public init(
        role: Role,
        content: String,
        toolCallID: String? = nil,
        toolCalls: [ToolCall] = [],
        reasoningContent: String? = nil,
        responseItems: [JSONValue]? = nil,
        taskID: UUID? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.reasoningContent = reasoningContent
        self.responseItems = responseItems
        self.taskID = taskID
    }
}

public struct ModelUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int?
    public let reasoningTokens: Int?

    public init(inputTokens: Int, outputTokens: Int, cachedTokens: Int? = nil, reasoningTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.reasoningTokens = reasoningTokens
    }
}

public struct ModelReply: Equatable, Sendable {
    public let content: String
    public let toolCalls: [ToolCall]
    public let reasoningContent: String?
    /// Opaque Responses output for stateless tool continuation; never displayed.
    public let responseItems: [JSONValue]?
    public let usage: ModelUsage?

    public init(content: String = "", toolCalls: [ToolCall] = [], reasoningContent: String? = nil,
                responseItems: [JSONValue]? = nil, usage: ModelUsage? = nil) {
        self.content = content
        self.toolCalls = toolCalls
        self.reasoningContent = reasoningContent
        self.responseItems = responseItems
        self.usage = usage
    }
}

public struct PendingApproval: Equatable, Identifiable, Sendable {
    public let id: String
    public let toolName: String
    public let title: String
    public let explanation: String

    public init(id: String, toolName: String, title: String, explanation: String) {
        self.id = id
        self.toolName = toolName
        self.title = title
        self.explanation = explanation
    }
}

public enum AgentEvent: Equatable, Sendable {
    case response(String)
    case approvalRequired(PendingApproval)
}

public enum AgentRuntimeError: LocalizedError, Equatable {
    case unknownTool(String)
    case noPendingApproval
    case iterationLimit
    case emptyModelResponse
    case busy
    case approvalPending
    case providerChanged
    case multipleToolCalls

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "The model requested an unavailable tool: \(name)."
        case .noPendingApproval: return "There is no action waiting for approval."
        case .iterationLimit: return "The agent reached its tool-use limit for this request."
        case .emptyModelResponse: return "The model returned an empty response."
        case .busy: return "An agent request is already running."
        case .approvalPending: return "Approve or cancel the pending action before sending another request."
        case .providerChanged: return "The model server or access code changed. Start a new conversation before continuing."
        case .multipleToolCalls: return "The model requested several actions at once. None were executed. Ask for one step at a time."
        }
    }
}
