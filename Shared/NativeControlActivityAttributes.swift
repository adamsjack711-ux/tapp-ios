import ActivityKit
import Foundation

struct NativeControlActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var checkedAt: Date
    }
    var startedAt: Date
}
