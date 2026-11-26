import SwiftUI
import Combine

@main
struct TappLabApp: App {
    var body: some Scene { WindowGroup { LabView() } }
}

@MainActor
final class LabModel: ObservableObject {
    @Published var motion = TappMotion()
    @Published var status = "Parked in the centre"
    @Published var arrivals = 0
    @Published var hoverCount = 0
    @Published var hoverText = "No system hover observed"
    @Published var flags: [String: String] = [:]
    @Published var exportStatus = ""
    @Published var routeActive = false
    private var route: [CGPoint] = []
    private var ticking: Task<Void, Never>?
    private var events: [[String: String]] = []
    private var deadline = Date.distantPast

    func refresh() {
        flags = SystemPointerProbe.read()
        record("system state", values: flags)
    }

    func resize(_ size: CGSize) {
        stop("Canvas resized; old route cancelled")
        motion.resize(size)
        status = "Parked in the centre"
    }

    func move(_ point: CGPoint) {
        stop("Moving Tapp inside this app")
        motion.move(to: point)
        animate()
    }

    func runRoute() {
        guard motion.bounds != .zero else { return }
        stop("Following four local targets")
        arrivals = 0
        routeActive = true
        let w = motion.bounds.width, h = motion.bounds.height
        route = [.init(x: w * 0.2, y: h * 0.2), .init(x: w * 0.8, y: h * 0.2),
                 .init(x: w * 0.8, y: h * 0.8), .init(x: w * 0.2, y: h * 0.8)]
        motion.move(to: route.removeFirst())
        record("route started")
        animate()
    }

    func park() {
        stop("Returning to centre")
        motion.park()
        animate()
    }

    func stop(_ reason: String = "Stopped") {
        ticking?.cancel(); ticking = nil
        route.removeAll(); routeActive = false
        motion.stop(); status = reason
    }

    func sceneChanged(_ phase: ScenePhase) {
        if phase == .active { refresh() }
        else {
            stop("Paused outside Tapp Lab; route will not resume")
            record("scene inactive; movement stopped")
        }
    }

    private func animate() {
        deadline = Date().addingTimeInterval(20)
        ticking = Task { [weak self] in
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                guard Date() < deadline else { stop("20-second limit reached"); record("timeout"); return }
                let now = ProcessInfo.processInfo.systemUptime
                motion.step(seconds: now - last); last = now
                if !motion.moving {
                    if routeActive {
                        arrivals += 1
                        if !route.isEmpty { motion.move(to: route.removeFirst()) }
                        else {
                            routeActive = false
                            motion.park()
                            status = "Four arrivals; returning to centre"
                            record("four local target arrivals")
                        }
                    } else {
                        status = "Parked · local preview only"
                        ticking = nil
                        record("local movement finished", values: ["x": "\(motion.position.x)", "y": "\(motion.position.y)"])
                        return
                    }
                }
            }
        }
    }

    func record(_ event: String, values: [String: String] = [:]) {
        var entry = values
        entry["event"] = event
        entry["time"] = ISO8601DateFormatter().string(from: Date())
        events.append(entry)
        events = Array(events.suffix(80))
        let report: [String: Any] = ["scope": "Simulator only. Tapp is app-drawn; no HID input injected.",
            "flags": flags, "arrivals": arrivals, "systemHoverEvents": hoverCount, "events": events,
            "position": ["x": motion.position.x, "y": motion.position.y],
            "canvas": ["width": motion.bounds.width, "height": motion.bounds.height],
            "moving": motion.moving, "routeActive": routeActive, "status": status]
        do {
            let url = URL.documentsDirectory.appendingPathComponent("tapp-lab-results.json")
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            exportStatus = "Results saved locally"
        } catch { exportStatus = "Could not save: \(error.localizedDescription)" }
    }
}

struct LabView: View {
    @StateObject private var lab = LabModel()
    @Environment(\.scenePhase) private var phase
    private let mint = Color(red: 0.48, green: 0.95, blue: 0.76)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HITAPP / RESEARCH").font(.caption.monospaced()).foregroundStyle(mint)
                        Text("Meet Tapp.").font(.system(size: 38, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Image(systemName: "cursorarrow.motionlines").font(.largeTitle).foregroundStyle(mint)
                }
                Text("A little pointer with a clear destination.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Movement studio").font(.headline); Spacer(); Text("APP PREVIEW").font(.caption2.monospaced()).foregroundStyle(mint) }
                    Text("Tap a destination, or run the four-target route. This draws Tapp inside this app.").font(.caption).foregroundStyle(.secondary)
                    canvas.frame(height: 260)
                    HStack {
                        Label("\(lab.arrivals) arrivals", systemImage: "scope")
                        Spacer()
                        Text("x \(Int(lab.motion.position.x)) · y \(Int(lab.motion.position.y))").monospacedDigit()
                    }.font(.caption).foregroundStyle(.secondary)
                    Text(lab.status).font(.caption).accessibilityIdentifier("movementStatus")
                    HStack {
                        Button("Run route") { lab.runRoute() }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                        Button("Centre") { lab.park() }.buttonStyle(.bordered)
                        Button("Stop", role: .destructive) { lab.stop(); lab.record("manual stop") }.buttonStyle(.bordered)
                    }.font(.subheadline.bold())
                }.padding(16).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Apple pointer diagnostics").font(.headline); Spacer(); Button { lab.refresh() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh system diagnostics") }
                    ForEach(["AssistiveTouch", "Pointer Control", "Dwell Control", "Pointer feature gate"], id: \.self) { key in
                        HStack { Text(key); Spacer(); Text(lab.flags[key] ?? "unknown").foregroundStyle(lab.flags[key] == "on" ? mint : .secondary).fontWeight(.semibold) }.font(.subheadline)
                    }
                    Divider()
                    Text(lab.hoverText).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text("Read-only simulator flags. They do not prove a visible pointer or physical iPhone support.").font(.caption).foregroundStyle(.secondary)
                    Text(lab.exportStatus).font(.caption2).foregroundStyle(mint)
                }.padding(16).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
                Label("Separate simulator · no phone connection", systemImage: "iphone").font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }
        .background(Color(red: 0.035, green: 0.06, blue: 0.075))
        .preferredColorScheme(.dark)
        .onChange(of: phase) { _, value in lab.sceneChanged(value) }
        .onAppear { lab.refresh() }
    }

    private var canvas: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.3))
                Path { p in
                    p.move(to: .init(x: geometry.size.width / 2, y: 12)); p.addLine(to: .init(x: geometry.size.width / 2, y: geometry.size.height - 12))
                    p.move(to: .init(x: 12, y: geometry.size.height / 2)); p.addLine(to: .init(x: geometry.size.width - 12, y: geometry.size.height / 2))
                }.stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                ForEach(0..<4) { n in
                    let x = geometry.size.width * (n == 0 || n == 3 ? 0.2 : 0.8)
                    let y = geometry.size.height * (n < 2 ? 0.2 : 0.8)
                    Text("\(n + 1)").font(.caption.monospaced()).foregroundStyle(mint.opacity(0.7))
                        .frame(width: 34, height: 34).background(mint.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(mint.opacity(0.18))).position(x: x, y: y)
                }
                Circle().fill(mint).frame(width: 25, height: 25)
                    .overlay(HStack(spacing: 4) { Capsule().frame(width: 3, height: 6); Capsule().frame(width: 3, height: 6) }.foregroundStyle(.black.opacity(0.8)))
                    .shadow(color: mint.opacity(0.4), radius: 12)
                    .position(lab.motion.position).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { point in lab.move(point) }
            .onContinuousHover { state in
                switch state {
                case .active(let point):
                    lab.hoverCount += 1
                    lab.hoverText = "System hover: \(Int(point.x)), \(Int(point.y)) · \(lab.hoverCount) events"
                case .ended: lab.hoverText = "System hover exited · \(lab.hoverCount) events"
                }
            }
            .onAppear { lab.resize(geometry.size) }
            .onChange(of: geometry.size) { _, size in lab.resize(size) }
        }
    }
}
