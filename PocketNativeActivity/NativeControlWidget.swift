import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NativeControlWidgets: WidgetBundle {
    var body: some Widget { NativeControlWidget() }
}

struct NativeControlWidget: Widget {
    private let destination = URL(string: "pocketagent://screen-control")!
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NativeControlActivityAttributes.self) { context in
            Label(context.isStale ? "Native helper status unknown" : context.state.phase,
                  systemImage: "hand.point.up.left.fill")
                .padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.blue)
                .widgetURL(destination)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Label("hitapp", systemImage: "hand.point.up.left.fill")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "Status unknown · open hitapp" : context.state.phase).font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "questionmark.circle" : "hand.point.up.left.fill").foregroundStyle(.blue)
            } compactTrailing: { EmptyView() } minimal: {
                Image(systemName: context.isStale ? "questionmark.circle" : "hand.point.up.left.fill").foregroundStyle(.blue)
            }.widgetURL(destination)
        }
    }
}
