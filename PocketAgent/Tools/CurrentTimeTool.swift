import Foundation

struct CurrentTimeTool: AgentTool {
    let requiresApproval = false

    let definition = ToolDefinition(
        name: "current_time",
        description: "Returns the current local date, time, and time zone.",
        parameters: [
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false)
        ]
    )

    func approvalSummary(arguments: [String: JSONValue]) -> PendingApproval {
        PendingApproval(id: "", toolName: definition.name, title: "Check current time", explanation: "Read the current device time.")
    }

    func execute(arguments: [String: JSONValue]) async throws -> String {
        Date.now.formatted(date: .complete, time: .complete)
    }
}
