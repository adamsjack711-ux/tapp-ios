import SwiftUI
import UIKit

// Reuses exactly the same Core Animation artwork/effects as the external layer.
struct CursorPet: View {
    let companion: Companion
    var size: CGFloat
    var expression = "hello"
    var replay = 0
    @AppStorage("preview.quiet") private var quiet = false
    @AppStorage("preview.palette") private var palette = "original"
    @AppStorage("preview.customColor") private var customColor = "B6A0EA"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        CursorArtwork(companion: companion, size: size, motion: !quiet && !reduceMotion && scenePhase == .active, hex: CursorPalette.hex(palette, custom: customColor), expression: expression, replay: replay)
            .frame(width: size, height: size).allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct CursorArtwork: UIViewRepresentable {
    let companion: Companion
    let size: CGFloat
    let motion: Bool
    let hex: String
    let expression: String
    let replay: Int
    final class Coordinator { var lastExpression = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> DraftCursorView { DraftCursorView() }
    func updateUIView(_ view: DraftCursorView, context: Context) {
        guard Pet.cells.indices.contains(companion.index) else { return }
        view.configure(with: Pet.artwork(companion, hex: hex), size: size, style: companion.index, motion: motion)
        view.accentColor = DraftColorFromHex(hex)
        let identity = "\(companion.rawValue)-\(hex)-\(motion)-\(expression)-\(replay)"
        if context.coordinator.lastExpression != identity {
            context.coordinator.lastExpression = identity
            view.playExpression(expression)
        }
    }
}

// A native view in Tapp’s existing window receives only touches on the displayed pet while
// Tapp is foregrounded. Every other point returns nil to the ordinary app UI.
@MainActor private final class PetTapSurface: UIView {
    private var petRect: () -> CGRect
    private let target = UIButton(type: .custom)
    private var displayLink: CADisplayLink?
    private var wake: (() -> Void)?
    private var lastTap = -Double.infinity

    init(host: UIView, rect: @escaping () -> CGRect, name: String, quiet: Bool, wake: @escaping () -> Void) {
        self.petRect = rect; self.wake = wake
        super.init(frame: host.bounds)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear
        target.accessibilityLabel = "Wake \(name)"
        target.accessibilityHint = quiet ? "A soft glow, resting in place." : "A happy wiggle, smooth flight, then a soft landing."
        target.accessibilityIdentifier = "rocket.tap"
        target.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addSubview(target)
        host.addSubview(self)
        let link = CADisplayLink(target: self, selector: #selector(updateTarget))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common); displayLink = link
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
        resume()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func updateTarget() {
        let rect = petRect()
        target.isHidden = rect.isNull
        if !rect.isNull, let window { target.frame = convert(window.convert(rect, from: window.screen.coordinateSpace), from: window) }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, window?.windowScene?.activationState == .foregroundActive else { return nil }
        updateTarget()
        guard !target.isHidden, target.frame.contains(point) else { return nil }
        return target
    }
    @objc private func tapped() {
        let now = CACurrentMediaTime()
        guard now - lastTap >= 0.65, !petRect().isNull else { return }
        lastTap = now
        wake?()
    }
    @objc private func suspend() { isHidden = true; displayLink?.isPaused = true }
    @objc private func resume() {
        updateTarget()
        isHidden = window?.windowScene?.activationState != .foregroundActive
        displayLink?.isPaused = isHidden
    }
    func invalidate() {
        suspend(); displayLink?.invalidate(); displayLink = nil
        NotificationCenter.default.removeObserver(self)
        wake = nil; petRect = { .null }; removeFromSuperview()
    }
}

@MainActor final class RocketTourController: ObservableObject {
    static let shared = RocketTourController()
    static let duration: TimeInterval = 180
    @Published private(set) var running = false
    @Published private(set) var status = "Ready for a trip outside Tapp."
    private let directory = URL.documentsDirectory.appendingPathComponent("companion-runtime", isDirectory: true)
    private var request: [String: Any] = [:]
    private var session = ""
    private var deadline: Date?
    private var started: Date?
    private var receivedState = false
    private var poll: Task<Void, Never>?
    private var tapSurface: PetTapSurface?
    private var interactionRect = CGRect.null
    private var name = "Orbit"
    private var quietMotion = false

    func start(companion: Companion, size: Double, quiet: Bool) {
        stop()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            session = UUID().uuidString
            name = companion.rawValue; quietMotion = quiet
            request = ["session": session, "command": "start", "sequence": UUID().uuidString,
                       "name": name, "style": companion.index, "size": size, "quiet": quiet]
            request["color"] = CursorPalette.hex(UserDefaults.standard.string(forKey: "preview.palette") ?? "original",
                                               custom: UserDefaults.standard.string(forKey: "preview.customColor") ?? "B6A0EA")
            request["islandHome"] = UserDefaults.standard.object(forKey: "preview.islandHome") as? Bool ?? true
            try saveRequest()
            let pid = DraftSpawnCompanionRuntime(directory.path, session)
            guard pid > 0 else { throw NSError(domain: "SimulatorCompanion", code: Int(pid), userInfo: [NSLocalizedDescriptionKey: "Simulator companion could not start (\(pid))."]) }
            running = true; receivedState = false; started = Date()
            deadline = Date().addingTimeInterval(Self.duration + 2)
            status = "\(name) is getting ready…"
            poll = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.finishIfExpired()
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
                }
            }
        } catch { stop(reason: error.localizedDescription) }
    }
    private func saveRequest() throws {
        try JSONSerialization.data(withJSONObject: request).write(to: directory.appendingPathComponent("request.json"), options: .atomic)
    }
    private func command(_ action: String) {
        guard running else { return }
        request["command"] = action; request["sequence"] = UUID().uuidString
        do { try saveRequest() } catch { stop(reason: "Could not reach the simulator companion.") }
    }
    func wake() { command("wake") }
    func express(_ expression: String) {
        request["expression"] = expression
        command("expression")
    }
    func visitIsland(_ action: String) {
        request["islandAction"] = action
        command("island")
    }
    func rest() { command("rest") }
    func finishIfExpired() {
        guard running else { return }
        if let deadline, Date() >= deadline { stop(reason: "Three-minute preview finished. Start again whenever you like."); return }
        guard UIApplication.shared.applicationState == .active else { return }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           state["session"] as? String == session {
            receivedState = true
            if let x = state["x"] as? Double, let y = state["y"] as? Double,
               let width = state["width"] as? Double, let height = state["height"] as? Double {
                interactionRect = CGRect(x: x, y: y, width: width, height: height)
            } else { interactionRect = .null }
            switch state["phase"] as? String {
            case "hidden": status = "\(name) is tucked inside the Dynamic Island. Tap the island or Replay motion to come out."
            case "peeking": status = "\(name) is peeking out of the Dynamic Island."
            case "popping": status = "\(name) is popping out to say hello."
            case "hiding": status = "\(name) is tucking into the Dynamic Island."
            case "stopped": stop(reason: "Three-minute preview finished. Start again whenever you like."); return
            case "resting": status = "\(name) is resting at the edge. Tap them—even in another simulator app—to say hello."
            case "landing": status = "\(name) is gently settling at the edge."
            case "waking": status = "\(name) says hello! A little wiggle, then lift-off."
            case "quiet": status = "\(name) is here. Quiet motion keeps them still."
            default: status = quietMotion ? "\(name) is resting quietly." : "\(name) is on the way! They’ll settle after this little trip."
            }
            installTapTargetIfNeeded()
        } else if !receivedState, let started, Date().timeIntervalSince(started) > 5 {
            stop(reason: "The simulator touch runtime did not respond. Please restart the preview.")
        }
    }
    private func installTapTargetIfNeeded() {
        guard running, tapSurface == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let host = scene.windows.first(where: { !$0.isHidden && $0.windowLevel == .normal }) else { return }
        var controller = host.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        tapSurface = PetTapSurface(host: controller?.view ?? host, rect: { [weak self] in self?.interactionRect ?? .null }, name: name, quiet: quietMotion) { [weak self] in self?.wake() }
    }
    func stop(reason: String = "Stopped. Companion removed.") {
        if running {
            request["command"] = "stop"; request["sequence"] = UUID().uuidString
            try? saveRequest()
        }
        running = false; deadline = nil; started = nil
        poll?.cancel(); poll = nil
        tapSurface?.invalidate(); tapSurface = nil; interactionRect = .null
        status = reason
    }
}
struct RocketTourView: View {
    @ObservedObject private var tour = RocketTourController.shared
    @AppStorage("preview.companion") private var companion: Companion = .orbit
    @AppStorage("preview.size") private var size = 32.0
    @AppStorage("preview.quiet") private var quiet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CursorPet(companion: companion, size: 100).padding(10).background(Look.soft, in: Circle())
                Text("A little trip outside.").font(.system(.title, design: .rounded, weight: .semibold)).multilineTextAlignment(.center)
                Text("Tap your floating companion, even in another simulator app. A happy wiggle, a smooth flight, then one soft landing.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Picker("Tour companion", selection: $companion) {
                    ForEach(Companion.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                VStack(spacing: 10) {
                    HStack { Text("Cursor size"); Spacer(); Text("\(Int(size)) pt").monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: $size, in: 28...56, step: 1).accessibilityLabel("Tour cursor size")
                    Toggle("Quiet motion", isOn: $quiet)
                    Text(quiet || reduceMotion ? "Resting still. A soft glow acknowledges your tap." : "Wake · glide · land. A little bubble trail follows, then fades as your companion settles.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.subheadline)
                MainButton(title: tour.running ? "Restart companion preview" : "Start companion preview", icon: "paperplane.fill", action: start)
                Button { tour.rest() } label: { Label("Rest at edge", systemImage: "moon").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).disabled(!tour.running)
                Button("Stop and remove companion", role: .destructive) { tour.stop() }.frame(minHeight: 44).disabled(!tour.running)
                Text(tour.status).font(.caption).foregroundStyle(Look.sage).multilineTextAlignment(.center).accessibilityIdentifier("rocket.status")
                Text("Simulator draft · three-minute preview").font(.caption.bold())
                Text("Tap-to-wake uses a native simulator helper that ends after three minutes. Stop removes the companion sooner. This is a simulator experiment; physical iPhone support is still unproven.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).padding(.bottom, 30)
        }.background(Look.background).navigationTitle("Companion tour").navigationBarTitleDisplayMode(.inline)
        .task { if ProcessInfo.processInfo.arguments.contains("--rocket-tour") { start() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { tour.finishIfExpired() } }
        .onChange(of: companion) { _, _ in refresh() }
        .onChange(of: size) { _, _ in refresh() }
        .onChange(of: quiet) { _, _ in refresh() }
        .onChange(of: reduceMotion) { _, _ in refresh() }
    }
    private func start() { tour.start(companion: companion, size: size, quiet: quiet || reduceMotion) }
    private func refresh() { if tour.running { start() } }
}
