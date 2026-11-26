import SwiftUI
import UIKit

struct ScreenControlView: View {
    @ObservedObject var screen: ScreenControlModel
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRunnerStop = false
    @State private var confirmingRunnerStart = false
    @ObservedObject private var native = NativeControlModel.shared

    var body: some View {
        NavigationStack {
            Form {
                TappCursorSection()
                Section("Native screen control") {
                    Label("No XCTest · own Dynamic Island icon", systemImage: "hand.tap")
                    Text("Native access stays enabled until you turn it off. Requested reads, highlights, scrolling and supported navigation run without repeated access prompts. Uses local OCR, not an accessibility tree; typing is not supported yet. Keep the phone unlocked and untouched during a command.").font(.footnote)
                }
                #if DEBUG
                NativeControlSetupSection()
                #endif
                Section("Status") {
                    Text(screen.status).font(.footnote).textSelection(.enabled)
                }

                Section {
                    Picker("Interaction", selection: $screen.interactionMode) {
                        ForEach(ScreenInteractionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .disabled(screen.isEnabled || screen.isWorking || app.isWorking)
                    TextField("Allowed app bundle ID", text: $screen.targetBundleID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(screen.isEnabled || screen.isWorking || app.isWorking)
                    Toggle("Screen Control · stay enabled", isOn: Binding(
                        get: { screen.isEnabled },
                        set: { enabled in
                            if enabled { screen.enable() }
                            else { app.stop(); screen.stop() }
                        }
                    ))
                    .disabled(screen.isWorking || app.isWorking || native.busy)
                    Button("Stop screen control", role: .destructive) {
                        app.stop()
                        screen.stop()
                    }
                } header: { Text("Saved access & app scope") } footer: {
                    Text("Your choice, app scope and mode survive relaunch. Guide me can only read and highlight. Stop control before changing mode or app. Requested Tapp gestures run without an extra approval card; iOS permission dialogs remain controlled by iOS. Manual previews stay local; agent screen text goes to your model only during requested work. No continuous recording. Stop cannot undo input already sent.")
                }

                Section("Manual proof of control") {
                    Button("Open app, read & preview screen") { screen.perform(.read) }
                    TextField("Exact visible control label", text: $screen.label)
                        .autocorrectionDisabled()
                    Picker("Observed control type", selection: $screen.elementType) {
                        Text("Any · must be unique").tag("")
                        Text("StaticText · screenshot OCR").tag("StaticText")
                    }
                    Button("Show me where · no tap") { screen.perform(.point) }
                        .disabled(screen.preview == nil)
                    Button("Tap this control") { screen.perform(.tap) }
                        .disabled(screen.preview == nil || screen.interactionMode == .guide)
                    Picker("Finger direction", selection: $screen.swipeDirection) {
                        ForEach(["up", "down", "left", "right"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Button("Swipe once") { screen.perform(.swipe) }
                        .disabled(screen.preview == nil || screen.interactionMode == .guide)
                    Text("Native typing is not supported yet. No fallback to XCTest.").font(.footnote)
                }
                .disabled(!screen.isEnabled || screen.isWorking || app.isWorking)

                Section {
                    Toggle("Navigation · stay enabled", isOn: Binding(
                        get: { native.homeNavigationEnabled },
                        set: { native.setHomeNavigationEnabled($0) }
                    )).disabled(native.busy || native.connected || app.isWorking || app.pendingApproval != nil)
                    Text(native.navigationStatus).font(.footnote)
                    Text("Say or type ‘Go Home’, ‘Open Settings’, ‘Open the App Switcher’, or ‘Swipe one Home page left/right’, then Send. These commands run without another approval card, including through the agent. No five-minute or ten-command expiry.").font(.footnote)
                    Button("Stop navigation", role: .destructive) {
                        native.setHomeNavigationEnabled(false)
                        app.stop(); native.stop(); LocalControlRoute.shared.stop()
                    }.disabled(!native.homeNavigationEnabled && !native.busy && !app.isWorking)
                } header: { Text("Navigation & Settings launch · experimental") } footer: {
                    Text("Separate scope, remembered across launches. Settings is the first supported app-launch target. Opening it never changes a setting. No opening/closing app cards, unlocks or permission changes. Leaves the phone at its destination. Result screenshots stay local. Unchanged Dynamic Island/native engine, no XCTest.")
                }

                if screen.isEnabled {
                    Section {
                        Button("Ask hitapp about this app") {
                            app.draft = "Read the screen in \(screen.targetBundleID) and help me understand what I can do here. Show me where with a highlight before proposing any tap."
                            dismiss()
                        }
                        .disabled(screen.isWorking || app.isWorking || app.pendingApproval != nil)
                    } footer: {
                        Text("Prepares a question in the composer. Nothing is captured or sent until you send the request. Saved screen access means no extra read-permission card.")
                    }
                }

                if let result = screen.preview {
                    Section("Last screen · not live") {
                        ScreenPreviewCard(result: result)
                        DisclosureGroup("Screen text") {
                            Text(result.text).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }

                Section {
                    DisclosureGroup("Legacy XCTest · not used by the agent") {
                    Text("Starting this helper brings back Automation Running. Native operations refuse to run while it is active.").font(.footnote)
                    Button("Start legacy XCTest helper") { confirmingRunnerStart = true }
                        .disabled(screen.isWorking || screen.isEnabled || app.isWorking || native.connected || native.busy)
                    Button("Shut down legacy helper", role: .destructive) { confirmingRunnerStop = true }
                        .disabled(!screen.isPaired || screen.isWorking || app.isWorking)
                    HStack {
                        Button(screen.isPaired ? "Pair again" : "Pair with runner", action: screen.pair)
                        Spacer()
                        Button("Check legacy helper", action: screen.checkConnection).disabled(!screen.isPaired)
                    }.buttonStyle(.borderless).disabled(screen.isWorking || app.isWorking)
                    Button("Forget legacy pairing", role: .destructive, action: screen.forget)
                        .disabled(screen.isWorking || app.isWorking)
                    Link("iCTRL setup and source", destination: URL(string: "https://github.com/OpenMinis/iCTRL#installation")!)
                    }
                } footer: {
                    Text("An approved step briefly opens the target app, then tries to return here. iOS may suspend the operation. Start with Settings → General; never test with a payment, send, or deletion.")
                }
            }
            .navigationTitle("Screen Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Start the old automation engine?", isPresented: $confirmingRunnerStart) {
                Button("Start legacy helper") { screen.startRunner() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The XCTest helper brings back the Automation Running screen. Native Screen Control above does not need it. Starting the legacy helper does not enable or approve actions.")
            }
            .alert("Shut down the screen helper?", isPresented: $confirmingRunnerStop) {
                Button("Shut down", role: .destructive) { app.stop(); screen.stopRunner() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This stops the runner for all paired clients on this iPhone. hitapp chat will keep working. Pairing is retained.")
            }
        }
    }

}

struct ScreenPreviewCard: View {
    let result: ScreenResult
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Captured screen · not live", systemImage: "viewfinder")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            if let highlight = result.highlight {
                Text("Here: \(highlight.label)").font(.headline)
                Text("The outline marks the observed control. Nothing was tapped.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let data = result.screenshot, let image = UIImage(data: data) {
                Button { expanded = true } label: {
                    annotated(image).frame(maxHeight: 280).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enlarge captured screen\(result.highlight.map { ", highlighting \($0.label)" } ?? "")")
            }
            Text(result.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(2)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(context.date.timeIntervalSince(result.capturedAt) >= 120
                     ? "This capture has expired for actions. Read the screen again."
                     : "Captured \(result.capturedAt.formatted(date: .omitted, time: .shortened)). Read again if the screen changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(AgentPalette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AgentPalette.line))
        .sheet(isPresented: $expanded) {
            NavigationStack {
                if let data = result.screenshot, let image = UIImage(data: data) {
                    annotated(image).padding(20)
                        .navigationTitle(result.highlight?.label ?? "Captured screen")
                        .navigationBarTitleDisplayMode(.inline)
                        .safeAreaInset(edge: .bottom) {
                            Text("Captured preview, not a live overlay. No taps are sent from this image.")
                                .font(.footnote).foregroundStyle(.secondary).padding()
                        }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { expanded = false } } }
                }
            }
        }
    }

    private func annotated(_ image: UIImage) -> some View {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if let h = result.highlight {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 5))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange, lineWidth: 3))
                            .frame(width: h.width * geometry.size.width, height: h.height * geometry.size.height)
                            .position(x: (h.x + h.width / 2) * geometry.size.width,
                                      y: (h.y + h.height / 2) * geometry.size.height)
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(result.highlight.map { "Captured app screen. \($0.label) is outlined." } ?? "Captured app screen")
    }
}
