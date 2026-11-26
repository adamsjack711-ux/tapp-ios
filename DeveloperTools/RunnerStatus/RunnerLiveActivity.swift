import ActivityKit
import UIKit

/// Local status for the actual helper, not model activity. No screen capture,
/// network access, command execution or extra background entitlements.
@MainActor
@objc(PocketRunnerActivityBridge)
final class RunnerLiveActivity: NSObject {
    private static let shared = RunnerLiveActivity()
    private var activity: Activity<AutomationActivityAttributes>?
    private var running = false
    private var installed = false
    private var timer: Timer?
    private var updates: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    @objc static func install() {
        let owner = shared
        guard !owner.installed else { return }
        owner.installed = true
        let old = Activity<AutomationActivityAttributes>.activities
        owner.enqueue {
            for activity in old { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        owner.observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in shared.startIfVisible() } })
        owner.observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in shared.stop() } })
        owner.startIfVisible()
    }

    static func serverReady() {
        install()
        shared.running = true
        shared.startIfVisible()
        shared.refresh()
        shared.timer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            Task { @MainActor in shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        shared.timer = timer
    }

    static func serverStopped() { shared.stop() }

    private func startIfVisible() {
        guard activity == nil, UIApplication.shared.applicationState == .active,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: AutomationActivityAttributes(startedAt: .now),
                                            content: content(), pushType: nil)
            iCTRLUITests.logBuffer.append("PocketRunnerStatus: Live Activity started")
        } catch {
            iCTRLUITests.logBuffer.append("PocketRunnerStatus: Live Activity unavailable: \(error)")
        }
    }

    private func refresh() {
        guard running, let activity, activity.activityState == .active || activity.activityState == .stale else { return }
        let snapshot = content()
        enqueue { await activity.update(snapshot) }
    }

    private func content() -> ActivityContent<AutomationActivityAttributes.ContentState> {
        // A crash cannot reliably clean up. A missed heartbeat must not leave
        // an indefinitely green "running" icon.
        ActivityContent(state: .init(running: running, checkedAt: .now), staleDate: .now + 90)
    }

    private func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        guard let activity else { return }
        self.activity = nil
        enqueue { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = updates
        updates = Task { await previous?.value; await operation() }
    }
}
