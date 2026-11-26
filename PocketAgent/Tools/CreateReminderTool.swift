import EventKit
import Foundation

actor CreateReminderTool: AgentTool {
    let requiresApproval = true

    nonisolated let definition = ToolDefinition(
        name: "create_reminder",
        description: "Creates a reminder in Apple Reminders. Always include a short title. Optionally include notes and an ISO-8601 due date.",
        parameters: [
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "notes": .object(["type": .string("string")]),
                "due_date": .object([
                    "type": .string("string"),
                    "description": .string("Optional ISO-8601 date and time")
                ])
            ]),
            "required": .array([.string("title")]),
            "additionalProperties": .bool(false)
        ]
    )

    nonisolated func approvalSummary(arguments: [String: JSONValue]) -> PendingApproval {
        let title = arguments["title"]?.stringValue ?? "Untitled reminder"
        let dueDate = arguments["due_date"]?.stringValue.map { "\nDue: \($0)" } ?? ""
        return PendingApproval(
            id: "",
            toolName: definition.name,
            title: "Create reminder",
            explanation: title + dueDate
        )
    }

    func execute(arguments: [String: JSONValue]) async throws -> String {
        guard let title = arguments["title"]?.stringValue, !title.isEmpty else {
            throw ReminderError.missingTitle
        }

        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else {
            throw ReminderError.permissionDenied
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = arguments["notes"]?.stringValue
        reminder.calendar = store.defaultCalendarForNewReminders()

        if let rawDate = arguments["due_date"]?.stringValue,
           let date = ISO8601DateFormatter().date(from: rawDate) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
        }

        try store.save(reminder, commit: true)
        return "Created the reminder named \"\(title)\"."
    }
}

private enum ReminderError: LocalizedError {
    case missingTitle
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .missingTitle: return "The reminder needs a title."
        case .permissionDenied: return "hitapp does not have permission to create reminders."
        }
    }
}
