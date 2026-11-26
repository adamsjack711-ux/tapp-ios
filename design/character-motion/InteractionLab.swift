import SwiftUI
import UIKit

/// A real in-app overlay and deterministic local action. This does not synthesize iOS touches.
struct InteractionLab: View {
    let companion: Companion
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .body) private var panelHeight: CGFloat = 260
    @ScaledMetric(relativeTo: .body) private var buttonWidth: CGFloat = 144
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 52
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @AppStorage("preview.size") private var cursorSize = 32.0
    @AppStorage("preview.idle") private var idle = "Rest & fade"
    @AppStorage("preview.quiet") private var quiet = false
    @State private var gate = ActionGate()
    @State private var count = 0
    @State private var revision = 0
    @State private var allowed = true
    @State private var guideOnly = false
    @State private var scenario = "Normal"
    @State private var status = "Ready. Try a guided step or let Tapp add one."
    @State private var log: [String] = []
    @State private var task: Task<Void, Never>?
    @State private var cursor = CGPoint(x: 0.89, y: 0.22)
    @State private var opacity = 0.65
    @State private var targetVisible = false
    @State private var capturing = false
    @State private var capturedImage: UIImage?
    @State private var captureSheet = false
    @State private var note = ""
    @State private var canvasSize = CGSize(width: 320, height: 260)
    @FocusState private var typing: Bool
    private var active: Bool { scenePhase == .active }
    private var visible: Bool { CursorRules.visible(active: active, typing: typing, capturing: capturing) }
    private var animation: Animation? { quiet || reducedMotion ? nil : .smooth(duration: 0.65, extraBounce: 0) }

    var body: some View {
        Group {
            if embedded { screen } else {
                NavigationStack { screen.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
            }
        }
        .tint(Look.sage)
        .onDisappear { stop("Playground closed. Pending work cancelled.") }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stop("Paused while the app is inactive. Tap Run when you return.") } }
        .onChange(of: typing) { _, value in if value { stop("Tapp steps aside while you type.") } }
        .onChange(of: quiet) { _, _ in stop("Motion preference changed. Tapp is resting.") }
        .onChange(of: reducedMotion) { _, _ in stop("Reduce Motion changed. Tapp is resting.") }
        .onChange(of: guideOnly) { _, _ in stop("Help mode changed. Pending action cancelled.") }
        .onChange(of: allowed) { _, value in if !value { stop("Local actions disabled. Nothing further will run.") } }
        .sheet(isPresented: $captureSheet) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("A clear view.").font(.largeTitle.bold())
                        if let capturedImage { Image(uiImage: capturedImage).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18)) }
                        Text("This is a fresh image of the playground, rendered without Tapp or the target ring. It stays on this device.").font(.subheadline).foregroundStyle(.secondary)
                        Text("No photo-library permission or upload.").font(.caption)
                    }.padding(24)
                }.background(Look.background).navigationTitle("Local capture")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { captureSheet = false } } }
            }
        }
    }
    private var screen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A little room to try.").font(.system(.title2, design: .rounded, weight: .semibold))
                        Text("Real controls. Your chosen Tapp.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("LOCAL").font(.caption2.bold()).padding(8).background(Look.soft, in: Capsule())
                }
                canvas
                Label(status, systemImage: gate.phase == .verified ? "checkmark.circle.fill" : gate.phase == .failed ? "exclamationmark.circle" : "sparkles")
                    .font(.subheadline).foregroundStyle(Look.sage).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("lab.status")
                if dynamicType.isAccessibilitySize { VStack { runButton; stopButton } } else { HStack { runButton; stopButton } }
                HStack {
                    Button("Point at the button") { parkOnButton() }.frame(maxWidth: .infinity, minHeight: 44)
                    Button("Try idle") { runIdle() }.frame(maxWidth: .infinity, minHeight: 44)
                }.font(.subheadline)
                Toggle("Guide only · I’ll tap", isOn: $guideOnly)
                Toggle("Allow local counter action", isOn: $allowed)
                HStack {
                    Text("Test condition").font(.subheadline)
                    Spacer()
                    Picker("Test condition", selection: $scenario) { ForEach(["Normal", "Screen changes", "Unverified result"], id: \.self) { Text($0) } }.pickerStyle(.menu).disabled(gate.busy)
                }
                TextField("Try typing — Tapp steps aside", text: $note).textFieldStyle(.roundedBorder).focused($typing).submitLabel(.done).onSubmit { typing = false }.accessibilityIdentifier("lab.typing")
                Button { takeCapture() } label: { Label("Capture without Tapp", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 44) }.disabled(gate.busy)
                DisclosureGroup("What happened") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local action callbacks: \(gate.inputCount)").font(.caption.bold())
                        ForEach(Array(log.enumerated()), id: \.offset) { _, event in Text(event).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                    }.padding(.top, 8)
                }
                Text("The character and tap-through overlay work inside this app. “Add one” calls this app’s own counter action; it does not inject a touch into another app. Cross-app colour, movement and input remain a separate device test.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(22).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Look.background).navigationTitle("Tapp playground").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { typing = false } } }
    }
    private var runButton: some View { MainButton(title: guideOnly ? "Show me where" : "Let Tapp add one", icon: guideOnly ? "scope" : "play.fill") { run() }.disabled(gate.busy || (!allowed && !guideOnly)) }
    private var stopButton: some View { Button(role: .destructive) { stop("Stopped. No pending action will run.") } label: { Label("Stop", systemImage: "stop.fill").frame(minWidth: 64, minHeight: 52) }.disabled(!gate.busy && task == nil) }
    private var canvas: some View {
        GeometryReader { geometry in
            let point = CursorRules.position(x: cursor.x * geometry.size.width, y: cursor.y * geometry.size.height, width: geometry.size.width, height: geometry.size.height, size: cursorSize)
            counterSurface(width: geometry.size.width, height: geometry.size.height)
                .overlay {
                    if targetVisible && visible {
                        RoundedRectangle(cornerRadius: 20).stroke(Look.sage, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .frame(width: min(geometry.size.width - 18, buttonWidth + 14), height: buttonHeight + 12).position(x: geometry.size.width / 2, y: geometry.size.height * 0.65).allowsHitTesting(false).accessibilityHidden(true)
                    }
                    if visible {
                        CursorPet(companion: companion, size: cursorSize).opacity(opacity)
                            .position(x: point.x, y: point.y).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .onAppear { canvasSize = geometry.size }
                .onChange(of: geometry.size) { _, newSize in canvasSize = newSize; stop("Layout changed. Ready for a fresh observation.") }
        }.frame(height: panelHeight).clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Look.line, lineWidth: 1))
    }
    private func counterSurface(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Look.paper
            VStack(spacing: 5) {
                Text("THE LITTLE COUNTER").font(.caption2.weight(.semibold)).tracking(1)
                Text("\(count)").font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().accessibilityLabel("Counter \(count)")
            }.position(x: width / 2, y: height * 0.27)
            Button { increment(); event("Your tap reached the real button → \(count).") } label: {
                Text("Add one").font(.body.weight(.semibold)).frame(width: min(width - 32, buttonWidth), height: buttonHeight).foregroundStyle(Look.onSage).background(Look.sage, in: RoundedRectangle(cornerRadius: 17))
            }.buttonStyle(.plain).position(x: width / 2, y: height * 0.65).accessibilityIdentifier("lab.counter")
            Text("Your taps pass through Tapp").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width: width - 24).fixedSize(horizontal: false, vertical: true).position(x: width / 2, y: height * 0.91)
        }.frame(width: width, height: height)
    }
    private func increment() { count += 1; revision += 1 }
    private func event(_ text: String) { log.append(text); if log.count > 30 { log.removeFirst() } }
    private func stop(_ reason: String) {
        task?.cancel(); task = nil; gate.stop(); targetVisible = false; opacity = CursorRules.restingOpacity(idle); status = reason
    }
    private func parkOnButton() {
        stop("Tap Add one through Tapp — the overlay doesn’t block it."); typing = false; targetVisible = true
        withAnimation(animation) { cursor = CGPoint(x: 0.5, y: 0.65); opacity = 1 }
    }
    private func run() {
        task?.cancel(); typing = false; targetVisible = true; opacity = 1
        let observation: ActionGate.Observation
        do { observation = try gate.begin(count: count, revision: revision, now: ProcessInfo.processInfo.systemUptime, scope: "local-counter", allowed: allowed || guideOnly) }
        catch { status = "Not ready. Enable local actions and finish the current step."; return }
        let runScenario = scenario
        let onlyGuide = guideOnly
        status = "Found Add one. Pointing before the next step…"
        event("Observed counter \(count), revision \(revision).")
        withAnimation(animation) { cursor = CGPoint(x: 0.5, y: 0.65) }
        task = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.5)); try Task.checkCancellation()
                guard active, !typing else { stop("Paused. Start again when ready."); return }
                if onlyGuide { gate.finishGuide(); status = "Here it is. You take the next step — no action sent."; event("Guide finished; zero action callbacks."); task = nil; return }
                if runScenario == "Screen changes" { revision += 1; event("Injected a screen revision change before the action.") }
                try gate.authorize(observation, revision: revision, count: count, now: ProcessInfo.processInfo.systemUptime, scope: "local-counter", allowed: allowed, guideOnly: guideOnly)
                // The same application action as the button, not a synthetic OS gesture.
                if runScenario != "Unverified result" { increment() }
                event("Dispatched one local callback; no automatic retry.")
                let verified = gate.verify(observation, observedCount: count)
                status = verified ? "Verified: \(observation.count) → \(count). Exactly one added." : "Couldn’t verify a change. Stopped without retrying."
                event(verified ? "Observed exactly +1. PASS." : "No expected change observed. STOP.")
                targetVisible = false
                withAnimation(animation) { cursor = CGPoint(x: 0.89, y: 0.22); opacity = CursorRules.restingOpacity(idle) }
            } catch is CancellationError { return }
            catch {
                gate.fail(); targetVisible = false
                status = "Screen changed or access expired. Stopped before acting."
                event("Blocked before dispatch: \(error).")
            }
            task = nil
        }
    }
    private func runIdle() {
        stop("A quiet moment."); typing = false; targetVisible = false
        cursor = CGPoint(x: 0.89, y: 0.22); opacity = 1
        guard CursorRules.canTravel(quiet: quiet, reduceMotion: reducedMotion, busy: gate.busy, idleMode: idle) else { opacity = 0.65; status = "Still mode. No travel animation."; return }
        let mode = idle
        status = mode == "Edge trip" ? "One gentle edge trip, then rest." : "Settling, then fading. Tap Point to wake Tapp."
        task = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(150))
                if mode != "Fade away" { withAnimation(.easeInOut(duration: 2)) { cursor = CGPoint(x: 0.89, y: 0.78) } }
                try await Task.sleep(for: .seconds(2.1))
                withAnimation(.easeOut(duration: 0.8)) { opacity = CursorRules.restingOpacity(mode) }
                try await Task.sleep(for: .seconds(0.8)); task = nil
            } catch { }
        }
    }
    @MainActor private func takeCapture() {
        stop("Captured the playground without Tapp. Nothing uploaded."); typing = false; capturing = true
        // Render the same live counter surface, excluding its decorative overlay by construction.
        let renderer = ImageRenderer(content: counterSurface(width: canvasSize.width, height: canvasSize.height).environment(\.colorScheme, colorScheme))
        renderer.scale = 2
        capturedImage = renderer.uiImage; capturing = false
        if capturedImage != nil { event("Local counter image created with no cursor overlay."); captureSheet = true }
        else { status = "Capture unavailable. Nothing shared." }
    }
}
