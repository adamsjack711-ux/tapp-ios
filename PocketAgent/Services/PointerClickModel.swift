import Combine
import RorkDevice
import SwiftUI
import UIKit

/// A finite cursor operation, not the separately developed persistent cursor.
/// No touchscreen fallback: success requires one actual primary mouse click.
@MainActor
final class PointerClickModel: NSObject, ObservableObject {
    static let shared = PointerClickModel()
    @Published var showProof = false
    @Published private(set) var running = false
    @Published private(set) var status = "Ready for an inert cursor-click test."
    @Published private(set) var proofCount = 0
    var proofRect = CGRect.zero
    private var hover: CGPoint?
    private var hoverAt = -Double.infinity
    private var seenHover = false
    private var target = CGRect.zero
    private var capturedAt = -Double.infinity
    private var task: Task<Void, Never>?
    private weak var observedWindow: UIWindow?
    private var recognizer: UIHoverGestureRecognizer?
    private var initialCount = 0
    private var lastStatusAt = -Double.infinity

    func proofClicked() { proofCount += 1 }

    func startProof() {
        guard !running, showProof else { return }
        running = true; initialCount = proofCount
        hover = nil; seenHover = false; hoverAt = -.infinity; capturedAt = -.infinity
        target = .zero
        status = "Connecting. Cursor starts after an eight-second countdown; disconnect Mac preview. No message will be sent."
        let id = UUID()
        task = Task { [self] in
            defer {
                removeHover(); running = false; task = nil
                try? status.write(to: URL.applicationSupportDirectory.appendingPathComponent("PocketControl/cursor-click-result.txt"), atomically: true, encoding: .utf8)
            }
            do {
                let dispatch = try await NativeControlModel.shared.runCursorClick(operationID: id,
                    ready: { [weak self] in await self?.installHover() },
                    continueWhile: { [weak self] in await self?.mayContinue ?? false },
                    nextStep: { [weak self] elapsed in
                        guard let self else { throw CancellationError() }
                        return try await self.nextStep(elapsed)
                    }, beforeClick: { [weak self] in
                        guard let self else { throw CancellationError() }
                        try await self.verifyClick()
                    })
                try await Task.sleep(for: .milliseconds(500))
                guard proofCount == initialCount + 1 else { throw ClickError.noActivation }
                status = "PASS: the real cursor activated the inert button exactly once. \(dispatch) No message sent; no touchscreen fallback."
            } catch {
                status = "Cursor click not verified: \(error.localizedDescription) No automatic retry."
            }
        }
    }

    func stop() { task?.cancel() }

    private var mayContinue: Bool {
        running && showProof && UIApplication.shared.applicationState == .active && proofCount == initialCount
    }

    private func installHover() {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let gesture = UIHoverGestureRecognizer(target: self, action: #selector(observedHover(_:)))
        gesture.cancelsTouchesInView = false
        window.addGestureRecognizer(gesture)
        recognizer = gesture; observedWindow = window
        hover = nil; hoverAt = -.infinity; seenHover = false
    }

    private func removeHover() {
        if let recognizer { observedWindow?.removeGestureRecognizer(recognizer) }
        recognizer = nil; observedWindow = nil; hover = nil
    }

    @objc private func observedHover(_ gesture: UIHoverGestureRecognizer) {
        guard running, let window = observedWindow else { return }
        if gesture.state == .began || gesture.state == .changed {
            hover = gesture.location(in: window)
            hoverAt = ProcessInfo.processInfo.systemUptime; seenHover = true
        } else { hover = nil }
    }

    private func refreshTarget() async throws {
        guard mayContinue, let window = observedWindow else { throw CancellationError() }
        let before = hover, observationTime = hoverAt, started = ProcessInfo.processInfo.systemUptime
        let frame = try await NativeControlModel.shared.captureFrame()
        try Task.checkCancellation()
        guard mayContinue, !frame.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
        let matches = frame.items.filter { $0.label == "CLICK TEST" }
        guard matches.count == 1, let label = matches.first,
              proofRect.width > 120, proofRect.height > 50, window.bounds.contains(proofRect),
              proofRect.contains(CGPoint(x: (label.x + label.width / 2) * window.bounds.width,
                                         y: (label.y + label.height / 2) * window.bounds.height)) else { throw ClickError.target }
        target = proofRect.insetBy(dx: 12, dy: 12)
        let now = ProcessInfo.processInfo.systemUptime
        // No movement reports occur during capture; preserve a stationary,
        // previously fresh hover only when no change/exit event arrived.
        if before != nil, started - observationTime < 0.5, hover == before, hoverAt == observationTime {
            hoverAt += now - started
        }
        capturedAt = now
    }

    private func nextStep(_ elapsed: Double) async throws -> PocketPointerClickStep {
        guard mayContinue else { throw CancellationError() }
        var now = ProcessInfo.processInfo.systemUptime
        if now - capturedAt > 1.5 { try await refreshTarget(); now = ProcessInfo.processInfo.systemUptime }
        let movement: PocketPointerMotion
        if let hover, now - hoverAt < 0.5 {
            if target.contains(hover), hypot(hover.x - target.midX, hover.y - target.midY) < 12 { return .click }
            movement = PocketPointerSpeed.fast.toward(dxPoints: target.midX - hover.x, dyPoints: target.midY - hover.y)
        } else if !seenHover {
            movement = PocketPointerSpeed.precise.sweep(at: elapsed)
        } else { movement = .zero }
        if now - lastStatusAt > 0.5 {
            status = seenHover ? "Steering the real cursor using iOS hover feedback. Waiting for verified target arrival." : "Acquiring real pointer position. No click until observed on the target."
            lastStatusAt = now
        }
        return .move(movement)
    }

    private func verifyClick() async throws {
        try await refreshTarget()
        guard mayContinue, let hover, ProcessInfo.processInfo.systemUptime - hoverAt < 0.5,
              target.contains(hover), hypot(hover.x - target.midX, hover.y - target.midY) < 12 else { throw ClickError.target }
        status = "Pointer and target rechecked. Sending one primary-button click."
    }

    enum ClickError: LocalizedError {
        case target, noActivation
        var errorDescription: String? {
            switch self {
            case .target: "Fresh cursor position and target did not match. No click authorized."
            case .noActivation: "A mouse-button report was dispatched, but exactly one button activation was not observed."
            }
        }
    }
}

struct PointerClickProofView: View {
    @ObservedObject private var click = PointerClickModel.shared
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(spacing: 24) {
            Text("Real cursor click").font(.title.bold())
            Text("Inert test only. No text message is sent.\nAssistiveTouch stays on; Dwell stays off.")
                .font(.subheadline).multilineTextAlignment(.center)
            Spacer()
            Button("CLICK TEST") { click.proofClicked() }
                .font(.title2.bold()).buttonStyle(.borderedProminent)
                .frame(width: 260, height: 90)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: CursorClickFrame.self, value: geometry.frame(in: .global))
                })
                .onPreferenceChange(CursorClickFrame.self) { click.proofRect = $0 }
            Text("Verified activations: \(click.proofCount)").monospacedDigit()
            Spacer()
            Text(click.status).font(.footnote).frame(minHeight: 120)
            if click.running { Button("Stop cursor test", role: .destructive) { click.stop() } }
            else {
                Button("Run one cursor click") { click.startProof() }.buttonStyle(.borderedProminent)
                Button("Done") { click.showProof = false }
            }
        }.padding(28)
            .interactiveDismissDisabled(click.running)
            .onChange(of: phase) { _, value in if value != .active { click.stop() } }
            .onDisappear { click.stop() }
    }
}

private struct CursorClickFrame: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
