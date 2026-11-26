import SwiftUI
import UIKit

// Standalone simulator draft. No network, microphone, Photos, Keychain or input injection.
// RocketTour uses an explicitly simulator-only private display layer for a finite visual experiment.
enum Look {
    static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let background = adaptive(UIColor(red: 0.97, green: 0.965, blue: 0.94, alpha: 1), UIColor(red: 0.075, green: 0.10, blue: 0.085, alpha: 1))
    static let paper = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let sage = adaptive(UIColor(red: 0.20, green: 0.35, blue: 0.25, alpha: 1), UIColor(red: 0.74, green: 0.84, blue: 0.66, alpha: 1))
    static let soft = adaptive(UIColor(red: 0.89, green: 0.92, blue: 0.83, alpha: 1), UIColor(red: 0.18, green: 0.25, blue: 0.19, alpha: 1))
    static let onSage = adaptive(.white, UIColor(red: 0.10, green: 0.17, blue: 0.11, alpha: 1))
    static let line = Color.primary.opacity(0.09)
}
enum Companion: String, CaseIterable, Identifiable {
    case orbit = "Orbit", classic = "Classic", comet = "Comet"
    var id: String { rawValue }
    var index: Int { Self.allCases.firstIndex(of: self)! }
    var description: String {
        switch self { case .orbit: "Your curious little co-pilot."; case .classic: "A familiar friend, full of personality."; case .comet: "A small spark of encouragement." }
    }
}
struct Pet: View {
    let companion: Companion
    var size: CGFloat = 120
    @AppStorage("preview.palette") private var palette = "original"
    @AppStorage("preview.customColor") private var customColor = "B6A0EA"
    private static let tinted = NSCache<NSString, UIImage>()
    static func artwork(_ companion: Companion, hex: String) -> UIImage {
        guard cells.indices.contains(companion.index) else { return UIImage() }
        guard !hex.isEmpty else { return cells[companion.index] }
        let key = "\(companion.index)-\(hex)" as NSString
        if let cached = tinted.object(forKey: key) { return cached }
        let image = DraftTintedImage(cells[companion.index], DraftColorFromHex(hex))
        tinted.countLimit = 30
        tinted.setObject(image, forKey: key)
        return image
    }
    // Display a cell of the original sheet; leave the source artwork unchanged.
    static let cells: [UIImage] = {
        guard let url = Bundle.main.url(forResource: "Characters", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path)?.cgImage else { return [] }
        let side = image.width / 3
        return (0..<3).compactMap { index in
            image.cropping(to: CGRect(x: index * side, y: 0, width: side, height: image.height)).map { UIImage(cgImage: $0) }
        }
    }()
    var body: some View {
        Group {
            if Self.cells.indices.contains(companion.index) {
                Image(uiImage: Self.artwork(companion, hex: CursorPalette.hex(palette, custom: customColor))).resizable().scaledToFit()
            } else { Image(systemName: "sparkles").resizable().scaledToFit() }
        }.frame(width: size, height: size).accessibilityLabel(companion.rawValue + " companion")
    }
}
struct PetHalo: View {
    let companion: Companion
    var size: CGFloat = 156
    var body: some View {
        Pet(companion: companion, size: size * 0.87)
            .frame(width: size, height: size)
            .background(Look.soft, in: Circle())
            .padding(9)
            .overlay(Circle().stroke(Look.line, lineWidth: 1))
    }
}
struct MainButton: View {
    let title: String
    var icon: String = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.body.weight(.semibold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Look.onSage).background(Look.sage, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
struct ActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 19, weight: .medium)).foregroundStyle(Look.sage)
                    .frame(width: 42, height: 42).background(Look.soft, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(Look.paper, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Look.line, lineWidth: 0.7))
        }.buttonStyle(.plain)
    }
}
struct PreviewNote: View {
    var text = "Design preview · no live AI or phone actions"
    var body: some View { Text(text).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
}
private struct ChatMessage: Identifiable, Codable { var id = UUID(); let text: String; let isUser: Bool }
private struct SavedConversation: Identifiable, Codable {
    var id: String; var messages: [ChatMessage]
    var title: String { String((messages.first?.text ?? "New conversation").prefix(60)) }
}
private final class PreviewHistoryStore: ObservableObject {
    @Published var items: [SavedConversation] = []
    init() {
        if let data = UserDefaults.standard.data(forKey: "preview.history.v1"), let saved = try? JSONDecoder().decode([SavedConversation].self, from: data) { items = saved }
    }
    func save(id: String, messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }
        items.removeAll { $0.id == id }; items.insert(.init(id: id, messages: messages), at: 0); persist()
    }
    func remove(_ id: String) { items.removeAll { $0.id == id }; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: "preview.history.v1") } }
}

@main
struct TappPreviewApp: App {
    init() {
        let preferences = UserDefaults.standard
        if !preferences.bool(forKey: "preview.compactCursor.v2") {
            if preferences.object(forKey: "preview.size") == nil || preferences.double(forKey: "preview.size") == 42 {
                preferences.set(32.0, forKey: "preview.size")
            }
            preferences.set(true, forKey: "preview.compactCursor.v2")
        }
    }
    var body: some Scene { WindowGroup { MotionStudyView() } }
}
private struct PreviewRoot: View {
    @AppStorage("preview.companion") private var companion: Companion = .orbit
    @State private var tab = 0
    @AppStorage("preview.unsentDraft") private var draft = ""
    @State private var messages: [ChatMessage] = []
    @StateObject private var history = PreviewHistoryStore()
    @AppStorage("preview.activeChat") private var activeChat = UUID().uuidString
    @State private var pendingChat: SavedConversation?
    @State private var confirmHistory = false
    @State private var replyTask: Task<Void, Never>?
    @State private var replying = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: PreviewSheet?
    @State private var confirmDiscard = false
    @AppStorage("preview.conversationFirst") private var conversationFirst = false
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var welcomeTitleSize: CGFloat = 33
    enum PreviewSheet: String, Identifiable { case voice, settings, screen, lab; var id: String { rawValue } }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                chatScreen
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            HStack(spacing: 9) {
                                Text("tapp").font(.system(size: 26, weight: .bold, design: .rounded)).tracking(-1)
                                Text("PREVIEW").font(.system(size: 9, weight: .semibold)).tracking(1)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            Button { if draft.isEmpty { startNew() } else { confirmDiscard = true } } label: { Image(systemName: "square.and.pencil") }
                                .accessibilityLabel("New conversation")
                        }
                        ToolbarItem(placement: .topBarTrailing) { Button { focused = false; sheet = .settings } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Settings") }
                    }
                    .navigationBarTitleDisplayMode(.inline)
            }.tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(0)
            NavigationStack { CompanionView(companion: $companion) }
                .tabItem { Label("My Tapp", systemImage: "sparkles") }.tag(1)
            NavigationStack { HistoryView(store: history) { item in if draft.isEmpty { open(item) } else { pendingChat = item; confirmHistory = true } } }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(2)
        }
        .tint(Look.sage)
        .sheet(item: $sheet) { item in
            switch item {
            case .lab: InteractionLab(companion: companion)
            case .voice: VoicePreview(companion: companion, existingDraft: draft) { text in draft = text; sheet = nil; send() }
            case .settings: SettingsPreview(companion: companion, conversationFirst: $conversationFirst)
            case .screen: ScreenHelpPreview(companion: companion)
            }
        }
        .confirmationDialog("Keep your unsent draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard draft and start new chat", role: .destructive) { startNew() }
            Button("Keep writing", role: .cancel) { }
        }
        .confirmationDialog("Keep your unsent draft?", isPresented: $confirmHistory, titleVisibility: .visible) {
            Button("Discard draft and open conversation", role: .destructive) { if let pendingChat { draft = ""; open(pendingChat) }; pendingChat = nil }
            Button("Keep writing", role: .cancel) { pendingChat = nil; tab = 0 }
        }
        .onAppear { if messages.isEmpty, let saved = history.items.first(where: { $0.id == activeChat }) { messages = saved.messages } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopReply() } }
    }
    private func stopReply() { replyTask?.cancel(); replyTask = nil; replying = false }
    private func startNew() { stopReply(); draft = ""; messages = []; activeChat = UUID().uuidString }
    private func open(_ item: SavedConversation) { stopReply(); activeChat = item.id; messages = item.messages; tab = 0 }
    private var chatScreen: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if messages.isEmpty { welcome }
                    ForEach(messages) { item in
                        if item.isUser {
                            HStack { Spacer(minLength: 35); Text(item.text).padding(16).background(Look.soft, in: RoundedRectangle(cornerRadius: 21)) }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 3) { Pet(companion: companion, size: 34); Text("Tapp").font(.caption.weight(.semibold)) }
                                Text(item.text).lineSpacing(5)
                                Text("Sample reply · no AI request").font(.caption2).foregroundStyle(.secondary)
                                ActionRow(title: "Help with a screenshot", subtitle: "You choose what to share", icon: "viewfinder") { sheet = .screen }
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .background(Look.background)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            if conversationFirst {
                HStack(spacing: 12) {
                    Pet(companion: companion, size: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RIGHT HERE WITH YOU").font(.system(size: 10, weight: .medium)).tracking(1.4).foregroundStyle(.secondary)
                        Text("Hi, I’m Tapp.").font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1)
                    }
                }.padding(.vertical, 10)
                Text("What would make your day a little easier?").font(.subheadline).foregroundStyle(.secondary)
                ActionRow(title: "Think something through", subtitle: "Turn a tangle into a next step", icon: "sparkles") { draft = "Help me think through "; focused = true }
                ActionRow(title: "Talk it out", subtitle: "Dictate at your own pace", icon: "mic") { sheet = .voice }
            } else {
                VStack(spacing: 16) {
                    PetHalo(companion: companion, size: 142).padding(.top, 4)
                    VStack(spacing: 9) {
                        Text("YOUR LITTLE CO-PILOT").font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(.secondary)
                        Text("What shall we\ndo together?").font(.system(size: welcomeTitleSize, weight: .semibold, design: .rounded)).tracking(-1)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text("A question, a task, a little nudge.\nI’m here when you need a hand.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }.frame(maxWidth: .infinity)
                MainButton(title: "Tell Tapp what’s on your mind", icon: "mic") { sheet = .voice }
                Text("Dictate, review, then send").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            ActionRow(title: "Help with my screen", subtitle: "Choose a screenshot or an allowed app", icon: "viewfinder") { sheet = .screen }
            ActionRow(title: "Try Tapp in action", subtitle: "A working playground for your companion", icon: "cursorarrow.rays") { sheet = .lab }
        }
    }
    private var composer: some View {
        VStack(spacing: 7) {
            if replying { HStack { ProgressView(); Text("Preparing a sample reply…").font(.caption); Spacer(); Button("Stop reply") { stopReply() }.font(.caption.bold()) }.padding(.horizontal, 10) }
            VStack(spacing: 5) {
                TextField("What can I help with?", text: $draft, axis: .vertical)
                    .lineLimit(1...4).focused($focused).padding(.horizontal, 6).padding(.top, 6).frame(minHeight: 37)
                    .accessibilityIdentifier("preview.composer")
                HStack(spacing: 4) {
                    Button { focused = false; sheet = .screen } label: { Image(systemName: "plus").frame(width: 40, height: 40) }.accessibilityLabel("Attach screenshot")
                    Text("Ask, show, or tell me").font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { focused = false; sheet = .voice } label: { Image(systemName: "mic").frame(width: 40, height: 40) }.accessibilityLabel("Dictate message")
                    Button(action: send) { Image(systemName: "arrow.up").font(.headline).frame(width: 40, height: 40).background(Look.soft, in: Circle()) }
                        .disabled(replying || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Preview send")
                }
            }.padding(10).background(Look.paper, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Look.line, lineWidth: 1))
            PreviewNote()
        }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 6).background(Look.background)
    }
    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !replying else { return }
        messages.append(.init(text: text, isUser: true)); draft = ""; focused = false
        history.save(id: activeChat, messages: messages); replying = true
        replyTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.5)); try Task.checkCancellation()
                messages.append(.init(text: "Let’s take it one step at a time. Show me the screen, or tell me which part feels confusing.", isUser: false))
                history.save(id: activeChat, messages: messages); replying = false; replyTask = nil
            } catch { }
        }
    }
}

private struct CompanionView: View {
    @Binding var companion: Companion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("preview.size") private var size: Double = 32
    @AppStorage("preview.idle") private var idle = "Rest & fade"
    @AppStorage("preview.quiet") private var quiet = false
    @State private var offset: CGFloat = 0
    @State private var opacity = 0.35
    @State private var demoTask: Task<Void, Never>?
    @State private var feedback = "Small, quiet, out of the way."
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                NavigationLink { InteractionLab(companion: companion, embedded: true) } label: { Label("Try Tapp in action", systemImage: "cursorarrow.rays").frame(maxWidth: .infinity, minHeight: 44) }
                NavigationLink { RocketTourView() } label: { Label("Companion across apps", systemImage: "paperplane").frame(maxWidth: .infinity, minHeight: 44) }
                VStack(spacing: 8) { PetHalo(companion: companion, size: 118); Text(companion.description).font(.subheadline).foregroundStyle(.secondary) }
                HStack(spacing: 10) {
                    ForEach(Companion.allCases) { candidate in
                        Button { demoTask?.cancel(); companion = candidate; offset = 0; opacity = 0.35 } label: {
                            VStack(spacing: 3) { Pet(companion: candidate, size: 78); Text(candidate.rawValue).font(.caption.weight(.semibold)) }
                                .padding(.vertical, 8).frame(maxWidth: .infinity)
                                .background(companion == candidate ? Look.soft : Look.paper, in: RoundedRectangle(cornerRadius: 20))
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(companion == candidate ? Look.sage : Look.line, lineWidth: companion == candidate ? 2 : 1))
                        }.buttonStyle(.plain).accessibilityLabel("Choose " + candidate.rawValue).accessibilityAddTraits(companion == candidate ? .isSelected : [])
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Cursor size"); Spacer(); Text("\(Int(size)) pt").foregroundStyle(.secondary).monospacedDigit() }.font(.subheadline)
                    Slider(value: $size, in: 28...56, step: 1).accessibilityLabel("Cursor size")
                    HStack { Text("When I’m idle").font(.subheadline); Spacer(); Picker("Idle behaviour", selection: $idle) { ForEach(["Rest & fade", "Edge trip", "Fade away", "Stay still"], id: \.self) { Text($0) } }.pickerStyle(.menu) }
                    Toggle(isOn: $quiet) { VStack(alignment: .leading, spacing: 3) { Text("Quiet motion").font(.subheadline); Text("Keep Tapp still and comfortable.").font(.caption).foregroundStyle(.secondary) } }
                }
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your screen stays yours.").font(.caption).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 3).fill(Look.line).frame(width: 160, height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(Look.line).frame(width: 120, height: 6)
                        Spacer()
                        Text(feedback).font(.caption2).foregroundStyle(.secondary)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    CursorPet(companion: companion, size: size).padding(.trailing, 10).padding(.top, 12).offset(y: offset).opacity(opacity).allowsHitTesting(false)
                }.frame(height: 164).background(Look.paper, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Look.line, lineWidth: 1)).clipped()
                MainButton(title: "Preview idle behaviour", icon: "play.fill", action: animate)
                DisclosureGroup("How Tapp stays out of your way") {
                    Text("Rest near an edge. Avoid text, keyboards and controls. Pause travel while you type or work. Hide during screen capture. Use a precise target marker for actions. Cross-app rendering still needs validation.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 5)
                }.font(.subheadline)
                PreviewNote(text: "Motion plays once · proposed behaviour only")
            }.padding(22).padding(.bottom, 28)
        }.background(Look.background).navigationTitle("My Tapp").navigationBarTitleDisplayMode(.inline)
            .onDisappear { demoTask?.cancel() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { resetMotion() } }
            .onChange(of: idle) { _, _ in resetMotion() }
            .onChange(of: quiet) { _, _ in resetMotion() }
            .onChange(of: systemReduceMotion) { _, _ in resetMotion() }
    }
    private func resetMotion() { demoTask?.cancel(); offset = 0; opacity = CursorRules.restingOpacity(idle); feedback = "Small, quiet, out of the way." }
    private func animate() {
        demoTask?.cancel(); offset = 0; opacity = 1
        guard !quiet, !systemReduceMotion, idle != "Stay still" else { opacity = 0.65; feedback = "Quiet mode · resting right here."; return }
        feedback = idle == "Edge trip" ? "A little edge-side trip, then rest." : idle == "Fade away" ? "Fades away until you need a hand." : "Settles near an edge, then fades."
        demoTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(100))
                if idle != "Fade away" { withAnimation(.easeInOut(duration: idle == "Edge trip" ? 3.2 : 1.5)) { offset = 66 } }
                try await Task.sleep(for: .milliseconds(idle == "Edge trip" ? 3200 : 1500))
                withAnimation(.easeOut(duration: 1.2)) { opacity = idle == "Fade away" ? 0 : 0.35 }
            } catch { }
        }
    }
}

private struct VoicePreview: View {
    let companion: Companion
    let existingDraft: String
    let send: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var state = 0
    @State private var transcript = "Help me understand what this screen is asking me to do."
    private let bars: [CGFloat] = [8, 19, 31, 18, 45, 29, 52, 34, 19, 39, 16, 27, 9]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    PetHalo(companion: companion).padding(.top, 18)
                    VStack(spacing: 10) {
                        Text(state == 0 ? "Take your time." : state == 1 ? "I’m listening." : "Sound like you?")
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1)
                        Text(state == 0 ? "A thought doesn’t have to be perfectly formed." : state == 1 ? "Get it all out. We’ll find the next step together." : "Edit your words before you choose Send.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    HStack(spacing: 5) { ForEach(Array(bars.enumerated()), id: \.offset) { _, height in Capsule().fill(Look.sage).frame(width: 5, height: state == 1 ? height : 8) } }
                        .frame(height: 60).accessibilityHidden(true)
                    if state == 2 {
                        TextField("Your words", text: $transcript, axis: .vertical).lineLimit(3...6).font(.title3)
                            .padding(18).background(Look.paper, in: RoundedRectangle(cornerRadius: 20)).accessibilityLabel("Review dictated message")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(state == 0 ? "Your voice, your pace" : "Listening preview").font(.headline)
                            Text(state == 0 ? "Speak, stop, review, then send." : "Sample words appear when you stop.").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Look.paper, in: RoundedRectangle(cornerRadius: 20))
                    }
                    MainButton(title: state == 0 ? "Try dictation" : state == 1 ? "Stop dictation" : "Send message", icon: state == 0 ? "mic" : state == 1 ? "stop.fill" : "arrow.up") {
                        if state < 2 { withAnimation(.easeInOut(duration: 0.2)) { state += 1 } } else { let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines); if !text.isEmpty { send(text) } }
                    }
                    .disabled(state == 2 && transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if state == 2 { Button("Try again") { state = 1 }.frame(minHeight: 44) }
                    PreviewNote(text: "Simulated dictation · microphone is off")
                }.padding(24)
            }.background(Look.background).navigationTitle("Talk to Tapp").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(Look.sage)
        .onAppear { if !existingDraft.isEmpty { transcript = existingDraft + "\n" + transcript } }
    }
}
private struct HistoryView: View {
    @ObservedObject var store: PreviewHistoryStore
    let open: (SavedConversation) -> Void
    @State private var search = ""
    @State private var deleteItem: SavedConversation?
    var filtered: [SavedConversation] { store.items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            Section("Saved on this simulator") {
                if filtered.isEmpty { Text(search.isEmpty ? "Your conversations will appear here." : "No matching conversations.").foregroundStyle(.secondary) }
                ForEach(filtered) { item in
                    Button { open(item) } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.headline).foregroundStyle(.primary); Text("Local draft · sample replies").font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 8)
                    }.swipeActions { Button("Delete", role: .destructive) { deleteItem = item } }
                }
            }
            Section { Text("These draft conversations stay in Tapp Preview. They do not use or change the working app’s history.").font(.footnote).foregroundStyle(.secondary) }
        }.searchable(text: $search, prompt: "Find a conversation").scrollContentBackground(.hidden).background(Look.background).navigationTitle("History")
            .confirmationDialog("Delete this local draft conversation?", isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } }), titleVisibility: .visible) {
                Button("Delete conversation", role: .destructive) { if let deleteItem { store.remove(deleteItem.id) }; deleteItem = nil }
                Button("Keep conversation", role: .cancel) { deleteItem = nil }
            }
    }
}
private struct SettingsPreview: View {
    let companion: Companion
    @Binding var conversationFirst: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) { Pet(companion: companion, size: 64); VStack(alignment: .leading, spacing: 5) { Text("Make yourself at home.").font(.headline); Text("Tapp, on your terms.").font(.subheadline).foregroundStyle(.secondary) } }.padding(.vertical, 6)
                }.listRowBackground(Color.clear)
                Section("Compare the draft") { Toggle("Conversation-first home", isOn: $conversationFirst) }
                Section { NavigationLink { InteractionLab(companion: companion, embedded: true) } label: { Label("Interaction playground", systemImage: "cursorarrow.rays") } }
                Section("Your space") {
                    NavigationLink { AccountPreview() } label: { Label("Account & connection", systemImage: "person.crop.circle") }
                    NavigationLink { PermissionPreview() } label: { Label("Privacy & permissions", systemImage: "hand.raised") }
                    NavigationLink { InformationPreview(title: "Voice & shortcuts", text: "Keep the existing dictate → review → send flow, Siri and Action button setup. Continuous voice and “Hi Tapp” remain future work.") } label: { Label("Voice & shortcuts", systemImage: "mic") }
                    NavigationLink { RecoveryPreview() } label: { Label("Help & recovery", systemImage: "lifepreserver") }
                    NavigationLink { InformationPreview(title: "Developer tools", text: "Provider configuration, cursor and screenshot tests, the counter fixture, native navigation experiments, and local evidence remain accessible here in the implementation plan. This preview runs none of those diagnostics.") } label: { Label("Developer tools", systemImage: "hammer") }
                }
                Section { PreviewNote(text: "Separate SwiftUI concept app · no live connection") }
            }.scrollContentBackground(.hidden).background(Look.background).navigationTitle("Settings")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(Look.sage)
    }
}
private struct AccountPreview: View {
    @State private var connected = false
    var body: some View {
        Form {
            Section {
                Label(connected ? "Connected · example state" : "Tapp private beta", systemImage: connected ? "checkmark.circle" : "sparkles").font(.headline)
                Text("A private access code connects the real app to Tapp’s AI service.").foregroundStyle(.secondary)
                Button("Preview connected state") { connected = true }
            }
            Section("Keep in the real app") { Label("Access code in Keychain", systemImage: "key"); Label("Explicit connection check", systemImage: "wifi"); Label("Server allowance and expiry", systemImage: "clock") }
            Section { Text("No credentials are collected here. Connection checks and phone-control readiness are separate.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Account").scrollContentBackground(.hidden).background(Look.background)
    }
}
private struct PermissionPreview: View {
    @State private var screenshots = false
    @State private var control = false
    @State private var guide = "Guide me"
    var body: some View {
        Form {
            Section { Toggle("Share task screenshots", isOn: $screenshots); Toggle("Screen control", isOn: $control); Picker("Help mode", selection: $guide) { Text("Guide me").tag("Guide me"); Text("Act for me").tag("Act for me") } } footer: { Text("Preview switches only. They change no real permission.") }
            Section("Allowed app") { Label("Tapp Click Test · example", systemImage: "app") }
            Section { Text("The real app keeps explicit screenshot-sharing consent, app scope, iOS permission prompts, and Stop controls. Manual previews stay local. Shared task screenshots travel through Tapp’s backend to OpenAI.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Permissions").scrollContentBackground(.hidden).background(Look.background)
    }
}
private struct RecoveryPreview: View {
    @State private var result = ""
    var body: some View {
        Form {
            Section { Button("Check readiness") { result = "Preview: the real check names the blocker in account setup, cursor, or screen access." }; Button("Refresh Tapp") { result = "Preview: stops work and resets the cursor; preserves chats, account and permissions. Never replays input." }; Button("Stop screen control", role: .destructive) { result = "Preview: no further actions are sent. Stopping cannot undo input already sent." } }
            if !result.isEmpty { Section { Text(result).font(.subheadline) } }
            Section { PreviewNote(text: "No diagnostic or phone control is performed.") }
        }.navigationTitle("Help & recovery").scrollContentBackground(.hidden).background(Look.background)
    }
}
private struct InformationPreview: View {
    let title: String
    let text: String
    var body: some View { ScrollView { Text(text).font(.body).lineSpacing(6).padding(24) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Look.background).navigationTitle(title) }
}
private struct ScreenHelpPreview: View {
    let companion: Companion
    @Environment(\.dismiss) private var dismiss
    @State private var state = 0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if state == 0 {
                        Text("A hand with\nyour screen.").font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1)
                        Text("Start with what you’d like help understanding.").foregroundStyle(.secondary)
                        ActionRow(title: "Choose a screenshot", subtitle: "Preview it before sharing", icon: "photo") { state = 1 }
                        ActionRow(title: "Explain it", subtitle: "Make the screen easier to understand", icon: "bubble.left") { state = 2 }
                        ActionRow(title: "Show me where", subtitle: "Tapp points. You take the next step.", icon: "cursorarrow") { state = 2 }
                        NavigationLink { InteractionLab(companion: companion, embedded: true) } label: { Label("Test an action in the playground", systemImage: "hand.tap").frame(maxWidth: .infinity, minHeight: 52) }
                    } else {
                        PetHalo(companion: companion, size: 122).frame(maxWidth: .infinity)
                        Text(state == 1 ? "Check before sharing." : state == 2 ? "One step at a time." : state == 3 ? "Checking the result…" : state == 4 ? "All done." : "Let’s pause here.")
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        VStack(alignment: .leading, spacing: 12) {
                            Label(state == 1 ? "Screenshot placeholder" : state == 4 ? "The counter increased once." : state == 5 ? "Couldn’t verify the screen." : "Tapp Click Test · example", systemImage: state == 1 ? "photo" : "viewfinder").font(.headline)
                            Text(state == 1 ? "A real image is previewed here before you send it. No photo library is opened in this draft." : state == 5 ? "Check the allowed app and refresh Tapp. No action is retried automatically." : "Read the allowed screen, identify the control, then check what changed.").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Look.paper, in: RoundedRectangle(cornerRadius: 22))
                        if state == 3 {
                            MainButton(title: "Preview success", icon: "checkmark") { state = 4 }
                            Button("Preview error") { state = 5 }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                        Button(state == 3 ? "Stop now" : "Back to screen help", role: state == 3 ? .destructive : nil) { state = 0 }.frame(maxWidth: .infinity, minHeight: 44)
                    }
                    PreviewNote(text: "Simulated screen help · no capture, upload or gesture")
                }.padding(24)
            }.background(Look.background).navigationTitle("Screen help").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(Look.sage)
    }
}
