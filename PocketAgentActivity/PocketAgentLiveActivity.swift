import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PocketAgentActivityBundle: WidgetBundle {
    var body: some Widget { PocketAgentLiveActivity() }
}

struct PocketAgentLiveActivity: Widget {
    private let accent = Color(red: 0.36, green: 0.61, blue: 1)
    private let appURL = URL(string: "ictrl://start?callback=pocketagent://screen-control")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AutomationActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: symbol(context)).font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pocket Agent").font(.caption).foregroundStyle(.secondary)
                    Text(title(context)).font(.headline)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward").foregroundStyle(.secondary)
            }
            .padding(18)
            .activityBackgroundTint(Color(red: 0.06, green: 0.07, blue: 0.09))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(appURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(context)).font(.title2).foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Pocket Agent").font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title(context)).font(.headline)
                        Link(destination: appURL) {
                            Label("Open Pocket Agent",
                                  systemImage: "arrow.up.forward.app")
                                .font(.caption.weight(.semibold))
                        }
                        .tint(accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: symbol(context)).foregroundStyle(tint(context))
                    .accessibilityLabel(title(context))
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: symbol(context)).foregroundStyle(tint(context))
                    .accessibilityLabel("Pocket Agent: \(title(context))")
            }
            .widgetURL(appURL)
            .keylineTint(accent)
        }
    }

    private func title(_ context: ActivityViewContext<AutomationActivityAttributes>) -> String {
        if context.isStale { return "Helper status unknown · open Pocket Agent to check" }
        return context.state.running ? "Screen helper running · actions still need approval" : "Starting screen helper"
    }

    private func symbol(_ context: ActivityViewContext<AutomationActivityAttributes>) -> String {
        context.isStale ? "questionmark.circle" : "hand.point.up.left.fill"
    }

    private func tint(_ context: ActivityViewContext<AutomationActivityAttributes>) -> Color {
        context.isStale || !context.state.running ? .gray : accent
    }
}
