import SwiftUI
import AppIntents

@main
struct PocketAgentApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .task {
                    PocketAgentShortcuts.updateAppShortcutParameters()
                    await TappCursorModel.shared.restoreIfNeeded()
                    #if DEBUG
                    TappCursorModel.shared.runRequestedDiagnostic()
                    await model.runRequestedSwitcherDiagnostic()
                    #endif
                }
                .onOpenURL { url in
                    // A callback only returns to our UI. It cannot pair, enable
                    // control, send a prompt, or declare the helper connected.
                    guard url.scheme == "pocketagent", url.host == "screen-control" else { return }
                }
        }
    }
}
