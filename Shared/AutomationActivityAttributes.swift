import ActivityKit
import Foundation

/// Only generic status is shared with the system UI. Never put prompts,
/// credentials, target-app text, screenshots or typed values in an activity.
struct AutomationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Runner readiness only, never model progress or permission to act.
        var running: Bool
        var checkedAt: Date
    }

    var startedAt: Date
}
