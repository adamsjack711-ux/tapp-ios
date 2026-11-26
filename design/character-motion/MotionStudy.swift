import SwiftUI
import UIKit

enum CursorPalette {
    static let presets: [(id: String, name: String, hex: String)] = [
        ("original", "Original", ""),
        ("lavender", "Lavender", "B6A0EA"),
        ("mint", "Mint", "78CBA8"),
        ("coral", "Coral", "EF9B88"),
        ("sky", "Sky", "84BCEB")
    ]
    static func hex(_ id: String, custom: String) -> String {
        id == "custom" ? custom : presets.first(where: { $0.id == id })?.hex ?? ""
    }
    static func name(_ id: String) -> String {
        id == "custom" ? "Custom" : presets.first(where: { $0.id == id })?.name ?? "Original"
    }
}

struct CursorColorControls: View {
    @AppStorage("preview.palette") private var palette = "original"
    @AppStorage("preview.customColor") private var customColor = "B6A0EA"
    private var selection: Binding<Color> {
        Binding {
            Color(uiColor: DraftColorFromHex(customColor) ?? .systemPurple)
        } set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            customColor = String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
            palette = "custom"
        }
    }
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Make it yours").font(.caption.weight(.semibold))
                Spacer()
                Text(CursorPalette.name(palette)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(CursorPalette.presets, id: \.id) { preset in
                    Button { palette = preset.id } label: {
                        ZStack {
                            if preset.id == "original" {
                                Circle().fill(AngularGradient(colors: [Color(red: 0.80, green: 0.84, blue: 0.69), Color(red: 0.72, green: 0.67, blue: 0.94), Color(red: 1, green: 0.80, blue: 0.57), Color(red: 0.80, green: 0.84, blue: 0.69)], center: .center))
                            } else {
                                Circle().fill(Color(uiColor: DraftColorFromHex(preset.hex)!))
                            }
                            if palette == preset.id {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.75))
                            }
                        }.frame(width: 28, height: 28)
                            .padding(4)
                            .overlay(Circle().stroke(palette == preset.id ? Look.sage : .clear, lineWidth: 1.5))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(preset.name) cursor color")
                        .accessibilityAddTraits(palette == preset.id ? .isSelected : [])
                }
                ColorPicker("Custom cursor color", selection: selection, supportsOpacity: false)
                    .labelsHidden().frame(width: 44, height: 44)
                    .overlay(alignment: .bottom) {
                        if palette == "custom" { Circle().fill(Look.sage).frame(width: 4, height: 4).allowsHitTesting(false) }
                    }
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
        .background(Look.paper, in: RoundedRectangle(cornerRadius: 20))
    }
}

enum CursorExpression: String, CaseIterable, Identifiable {
    case hello, thinking, listening, celebrate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hello: "Say hello"
        case .thinking: "Thinking"
        case .listening: "Listening"
        case .celebrate: "Little win"
        }
    }
    var icon: String {
        switch self {
        case .hello: "hand.wave"
        case .thinking: "ellipsis.bubble"
        case .listening: "waveform"
        case .celebrate: "sparkles"
        }
    }
    var detail: String {
        switch self {
        case .hello: "A happy wiggle and a soft stretch."
        case .thinking: "A curious tilt, a pause, then back to you."
        case .listening: "Three gentle pulses. All attention on you."
        case .celebrate: "A little hop and a sprinkle of confetti."
        }
    }
}

struct ExpressionHalo: View {
    let companion: Companion
    let size: CGFloat
    let expression: CursorExpression
    let replay: Int
    var body: some View {
        CursorPet(companion: companion, size: size * 0.87, expression: expression.rawValue, replay: replay)
            .frame(width: size, height: size)
            .background(Look.soft, in: Circle()).padding(9)
            .overlay(Circle().stroke(Look.line, lineWidth: 1))
    }
}

struct AnimationStudio: View {
    @AppStorage("preview.companion") private var companion: Companion = .orbit
    @AppStorage("preview.quiet") private var quiet = false
    @AppStorage("preview.islandHome") private var islandHome = true
    @Binding var expression: CursorExpression
    @Binding var replay: Int
    var play: (CursorExpression) -> Void
    var visitIsland: (String) -> Void
    @State private var islandPreview = "A cozy place to tuck away."
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 14) {
                        ExpressionHalo(companion: companion, size: 96, expression: expression, replay: replay)
                        Text(expression.title).font(.system(.title2, design: .rounded, weight: .semibold))
                        Text(expression.detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(CursorExpression.allCases) { choice in
                            Button { play(choice) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: choice.icon).font(.title3)
                                    Text(choice.title).font(.subheadline.weight(.medium))
                                    Spacer(minLength: 0)
                                    if expression == choice { Image(systemName: "checkmark").font(.caption.bold()) }
                                }.padding(12).frame(maxWidth: .infinity, minHeight: 48)
                                    .background(expression == choice ? Look.soft : Look.paper, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).accessibilityLabel("Preview \(choice.title)")
                                .accessibilityAddTraits(expression == choice ? .isSelected : [])
                        }
                    }
                    MainButton(title: "Replay \(expression.title.lowercased())", icon: "play.fill") { play(expression) }
                    CursorColorControls()
                    VStack(alignment: .leading, spacing: 12) {
                        Label("A little hiding place", systemImage: "capsule.fill").font(.headline)
                        Picker("Companion home", selection: $islandHome) {
                            Text("Dynamic Island").tag(true)
                            Text("Screen edge").tag(false)
                        }.pickerStyle(.segmented)
                        HStack(spacing: 8) {
                            islandButton("Peek", icon: "eyes", action: "peek")
                            islandButton("Pop out", icon: "arrow.up.right", action: "pop")
                            islandButton("Tuck in", icon: "moon", action: "hide")
                        }
                        islandButton("Come home", icon: "arrow.down.right", action: "arrive")
                        Text(islandPreview).font(.caption).foregroundStyle(.secondary)
                    }.padding(12).background(Look.paper, in: RoundedRectangle(cornerRadius: 20))
                    Toggle("Quiet motion", isOn: $quiet).font(.subheadline)
                }.padding(20)
            }.background(Look.background)
                .navigationTitle("Animation studio").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(Look.sage)
    }
    private func islandButton(_ title: String, icon: String, action: String) -> some View {
        Button {
            islandPreview = "Watch the Dynamic Island at the top of the screen."
            visitIsland(action)
        } label: {
            Label(title, systemImage: icon).font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Look.soft, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(title) at Dynamic Island")
    }
}

struct MotionStudyView: View {
    @ObservedObject private var tour = RocketTourController.shared
    @AppStorage("preview.companion") private var companion: Companion = .orbit
    @AppStorage("preview.size") private var size = 32.0
    @AppStorage("preview.quiet") private var quiet = false
    @AppStorage("preview.palette") private var palette = "original"
    @AppStorage("preview.customColor") private var customColor = "B6A0EA"
    @AppStorage("preview.islandHome") private var islandHome = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @State private var mode = "Everyday help"
    @State private var attachment = false
    @State private var showMotion = false
    @State private var showVoice = false
    @State private var showAnimations = false
    @State private var expression: CursorExpression = .hello
    @State private var expressionReplay = 0
    @State private var sent = ""
    @FocusState private var typing: Bool

    private var phaseLabel: String {
        if !tour.running { return "Ready when you are" }
        if quiet || reduceMotion { return "Here, quietly" }
        if tour.status.contains("tucked") { return "Tucked away, still here" }
        if tour.status.contains("peeking") { return "A little peek" }
        if tour.status.contains("popping") { return "Hello again" }
        if tour.status.contains("tucking") { return "Back to my hiding place" }
        if tour.status.contains("hello") { return "A little hello" }
        if tour.status.contains("settling") { return "Coming in softly" }
        if tour.status.contains("resting") { return "Resting nearby" }
        return "Off we go"
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text("tapp").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("MOTION STUDY").font(.caption2.weight(.semibold)).tracking(1.3)
                            .foregroundStyle(Look.sage).padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Look.soft, in: Capsule())
                        Spacer()
                        Button { showMotion = true } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                        }.accessibilityLabel("Motion settings")
                    }
                    VStack(spacing: 10) {
                        Button(action: replay) {
                            ExpressionHalo(companion: companion, size: 88, expression: expression, replay: expressionReplay)
                        }.buttonStyle(.plain).accessibilityLabel("Wake \(companion.rawValue)")
                        Label(phaseLabel, systemImage: tour.running ? "sparkle" : "moon")
                            .font(.caption.weight(.medium)).foregroundStyle(Look.sage)
                        Text("A little help.\nA little personality.")
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text("Talk, type, or show me.\nWe’ll take it one step at a time.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(.top, 2)
                    HStack(spacing: 10) {
                        ForEach(Companion.allCases) { choice in
                            Button { companion = choice } label: {
                                VStack(spacing: 3) {
                                    Pet(companion: choice, size: 48)
                                    Text(choice.rawValue).font(.caption.weight(.medium))
                                }.frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(companion == choice ? Look.soft : Look.paper, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("\(choice.rawValue)\(companion == choice ? ", selected" : "")")
                        }
                    }
                    CursorColorControls()
                    if !sent.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(sent).font(.subheadline.weight(.medium))
                            Text("Let’s make it a little easier. We can start with one small step.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Sample conversation · no live AI").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                            .background(Look.paper, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        HStack(spacing: 8) {
                            suggestion("Make this simpler", icon: "sparkles")
                            suggestion("Help with my screen", icon: "viewfinder")
                        }
                    }
                }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .background(Look.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showMotion) { NavigationStack { RocketTourView().toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showMotion = false } }
            } } }
            .sheet(isPresented: $showVoice) { voiceReview }
            .sheet(isPresented: $showAnimations) {
                AnimationStudio(expression: $expression, replay: $expressionReplay, play: playExpression, visitIsland: visitIsland)
            }
        }
        .tint(Look.sage)
        .task { start() }
        .onChange(of: companion) { _, _ in start() }
        .onChange(of: islandHome) { _, _ in if tour.running { start() } }
        .task(id: "\(palette)-\(customColor)") {
            // Let the native picker settle before refreshing the external preview.
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            if tour.running { start() }
        }
        .onChange(of: quiet) { _, _ in if tour.running { start() } }
        .onChange(of: reduceMotion) { _, _ in if tour.running { start() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { tour.finishIfExpired() } }
        .onChange(of: typing) { _, focused in if focused { tour.rest() } }
    }
    private func suggestion(_ text: String, icon: String) -> some View {
        Button { draft = text; if text.contains("screen") { attachment = true } } label: {
            Label(text, systemImage: icon).font(.caption).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 9)
                .background(Look.paper, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Button(action: replay) { Label("Replay motion", systemImage: "play.fill") }
                Button { showAnimations = true } label: { Label("Animations", systemImage: "sparkles") }
                if tour.running { Button("Stop") { tour.stop() } }
            }.font(.caption.weight(.medium)).frame(minHeight: 44)
            VStack(alignment: .leading, spacing: 12) {
                if attachment {
                    HStack {
                        Label("Example screen", systemImage: "photo").font(.caption)
                        Spacer()
                        Button { attachment = false } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                        }.accessibilityLabel("Remove example screen")
                    }.foregroundStyle(Look.sage)
                }
                TextField("What’s on your mind?", text: $draft, axis: .vertical)
                    .lineLimit(2...4).focused($typing).font(.body)
                    .accessibilityIdentifier("study.prompt")
                HStack(spacing: 6) {
                    Button { attachment.toggle() } label: {
                        Image(systemName: "plus").font(.system(size: 19)).frame(width: 44, height: 44)
                    }.accessibilityLabel("Add example screen")
                    Menu {
                        Button("Everyday help") { mode = "Everyday help" }
                        Button("Explain a screen") { mode = "Explain a screen"; attachment = true }
                    } label: {
                        HStack(spacing: 5) { Text(mode); Image(systemName: "chevron.down").font(.caption2) }
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { typing = false; showVoice = true } label: {
                        Image(systemName: "mic").font(.system(size: 19)).frame(width: 44, height: 44)
                    }.accessibilityLabel("Preview dictation")
                    Button {
                        sent = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft = ""; attachment = false; typing = false; replay()
                    } label: {
                        Image(systemName: "arrow.up").font(.system(size: 19, weight: .semibold))
                            .frame(width: 44, height: 44).foregroundStyle(Look.onSage)
                            .background(Look.sage, in: Circle())
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                        .accessibilityLabel("Send preview message")
                }
            }.padding(16).background(Look.paper, in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Look.sage.opacity(0.18), lineWidth: 1))
            Text("Separate design draft · sample interactions")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12).background(Look.background)
    }
    private var voiceReview: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Label("A moment to say it your way.", systemImage: "waveform")
                    .font(.title2.weight(.semibold))
                Text("Dictation preview · microphone is off.").font(.subheadline).foregroundStyle(.secondary)
                Text("Help me make this feel a little simpler.")
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Look.paper, in: RoundedRectangle(cornerRadius: 22))
                MainButton(title: "Use this sample", icon: "checkmark") {
                    draft = "Help me make this feel a little simpler."; showVoice = false
                }
                Text("Review and edit it in the composer before sending.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(24).background(Look.background).navigationTitle("Your words")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showVoice = false } } }
        }.presentationDetents([.medium, .large])
    }
    private func start() { tour.start(companion: companion, size: size, quiet: quiet || reduceMotion) }
    private func replay() { if tour.running { tour.wake() } else { start() } }
    private func playExpression(_ choice: CursorExpression) {
        expression = choice
        expressionReplay += 1
        tour.express(choice.rawValue)
    }
    private func visitIsland(_ action: String) {
        if tour.running { tour.visitIsland(action) }
        else {
            start()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                tour.visitIsland(action)
            }
        }
    }
}
