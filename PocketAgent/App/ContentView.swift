import AppIntents
import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voice = VoiceTranscriber()
    @ObservedObject private var native = NativeControlModel.shared
    @ObservedObject private var messaging = MessageComposeModel.shared
    @ObservedObject private var tapp = TappCursorModel.shared
    @ObservedObject private var cursorClick = PointerClickModel.shared
    @StateObject private var launch = AgentLaunchCoordinator.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var showingSettings = false
    @State private var showingConnections = false
    @State private var showingScreenControl = false
    @State private var showingActionButton = false
    @State private var awaitingShortcutFocus = false
    @State private var dictationPrefix = ""
    @FocusState private var composerFocused: Bool
    @AppStorage(SettingsKeys.baseURL) private var providerURL = ""
    @AppStorage(SettingsKeys.model) private var providerModel = ""

    private var provider: ProviderPresentation {
        ProviderPresentation(baseURL: providerURL, model: providerModel)
    }
    private var inputLocked: Bool { model.isWorking || model.screen.isWorking || model.pendingApproval != nil }

    var body: some View {
        NavigationStack {
            conversation
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .background { AuraBackground() }
                .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AgentPalette.accent)
        .sheet(isPresented: $showingSettings, onDismiss: completeShortcutEntry) { SettingsView() }
        .sheet(isPresented: $showingConnections, onDismiss: completeShortcutEntry) { ConnectionsView(model: model, provider: provider) }
        .sheet(isPresented: $showingScreenControl, onDismiss: completeShortcutEntry) {
            ScreenControlView(screen: model.screen).environmentObject(model)
        }
        .sheet(isPresented: $showingActionButton, onDismiss: completeShortcutEntry) { ActionButtonSetupView() }
        .fullScreenCover(item: $messaging.request, onDismiss: { messaging.dismissed() }) { draft in
            MessageComposeSheet(draft: draft).ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $cursorClick.showProof) { PointerClickProofView() }
        .onChange(of: messaging.result) { _, result in
            if messaging.request == nil {
                model.messages.append(AppModel.ChatItem(speaker: .status, text: result))
            }
        }
        .onChange(of: voice.transcript) { _, transcript in
            if !transcript.isEmpty, !inputLocked {
                model.draft = dictationPrefix.isEmpty ? transcript : dictationPrefix + " " + transcript
            }
        }
        .onChange(of: voice.errorMessage) { _, message in
            if let message { model.errorMessage = message }
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let newItem else { return }
                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self) else { return }
                    model.attachImage(data)
                    composerFocused = true
                } catch { model.errorMessage = "The screenshot couldn’t be loaded. Please choose it again." }
                photoItem = nil
            }
        }
        .onChange(of: launch.composeRequestID) { _, _ in handleShortcutEntry() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { handleShortcutEntry() }
            else if phase == .background || voice.isRecording { voice.stop() }
        }
        .onChange(of: providerURL) { _, _ in model.modelConfigurationChanged() }
        .onChange(of: providerModel) { _, _ in model.modelConfigurationChanged() }
        .onChange(of: inputLocked) { _, locked in if locked { voice.stop() } else { completeShortcutEntry() } }
        .onChange(of: showingSettings) { _, shown in if shown { voice.stop() } }
        .onChange(of: showingScreenControl) { _, shown in if shown { voice.stop() } }
        .onChange(of: showingConnections) { _, shown in if shown { voice.stop() } }
        .onChange(of: showingActionButton) { _, shown in if shown { voice.stop() } }
        .onDisappear { voice.stop() }
        .task {
            handleShortcutEntry()
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--test-action-button") {
                _ = try? await SummonPocketAgentIntent().perform()
            }
            #endif
        }
    }

    private var connectionDescription: String {
        tapp.connected ? "Connected to your Mac" : tapp.enabled ? "Waiting for your Mac" : "Tapp is off"
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(AgentPalette.accent).frame(width: 8, height: 8)
                    .shadow(color: AgentPalette.accent.opacity(0.65), radius: 9)
                Text("hitapp").font(.system(size: 23, weight: .semibold)).tracking(-1)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Menu {
                Button("New conversation", systemImage: "square.and.pencil") {
                    voice.stop(); composerFocused = false; model.newConversation()
                }.disabled(model.isWorking || model.screen.isWorking)
                Button("Connections", systemImage: "network") { showingConnections = true }
                Button("Settings", systemImage: "slider.horizontal.3") { showingSettings = true }.disabled(inputLocked)
                Button("Guide me on screen", systemImage: "hand.point.up.left") { showingScreenControl = true }
                Button("Action button", systemImage: "bolt.fill") { showingActionButton = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18))
                    .foregroundStyle(AgentPalette.muted).frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.035), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
            .accessibilityLabel("Conversation, connections and settings")
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 8)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if model.messages.isEmpty { welcome }
                    ForEach(model.messages) { item in
                        ConversationMessage(item: item).id(item.id)
                    }
                    if let result = model.screen.preview {
                        ScreenPreviewCard(result: result)
                    }
                    if let data = native.navigationPreview, let image = UIImage(data: data) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Navigation result · local capture, not live", systemImage: "viewfinder")
                                .font(.footnote)
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280)
                            Text(native.navigationStatus).font(.caption)
                        }
                    }
                    if let approval = model.pendingApproval {
                        PendingActionCard(approval: approval, approve: model.approve, reject: model.reject)
                            .disabled(model.isWorking || model.screen.isWorking)
                    }
                    if model.isWorking {
                        WorkingCard(title: model.workPhase.title, detail: model.workPhase.detail, stop: model.stop)
                    }
                    if let error = model.errorMessage {
                        InlineErrorCard(message: error) { model.errorMessage = nil }
                    }
                    Color.clear.frame(height: 1).id("conversation-end")
                }
                .padding(.horizontal, 24)
                .padding(.top, model.messages.isEmpty ? 24 : 18)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: model.pendingApproval?.id) { _, _ in
                if model.pendingApproval != nil { composerFocused = false }
                scrollToEnd(proxy)
            }
            .onChange(of: model.isWorking) { _, _ in scrollToEnd(proxy) }
            .onChange(of: model.errorMessage) { _, _ in scrollToEnd(proxy) }
            .onChange(of: model.screen.preview?.observationID) { _, _ in scrollToEnd(proxy) }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 15) {
                Text("A LITTLE LESS TO DO")
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .foregroundStyle(AgentPalette.muted)
                Text("What's on\nyour mind, Jack?")
                    .font(.system(.largeTitle, design: .default, weight: .medium))
                    .tracking(-1.5).fixedSize(horizontal: false, vertical: true)
                Text("A thought, a task, a tiny favour.")
                    .font(.subheadline).foregroundStyle(AgentPalette.muted)
            }
            .padding(.top, 8)

            HStack(spacing: 10) {
                AuraCursor(size: 24)
                Button { showingConnections = true } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Right here with you.").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Circle().fill(tapp.connected ? AgentPalette.mint : AgentPalette.muted).frame(width: 5, height: 5)
                            Text(connectionDescription).font(.caption).foregroundStyle(AgentPalette.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .padding(16)
            .background(AgentPalette.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(AgentPalette.line, lineWidth: 1))
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, AgentPalette.accent.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1).padding(.horizontal, 30)
            }

            VStack(spacing: 0) {
                HStack {
                    Text("A PLACE TO START").tracking(1.4)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 10)).foregroundStyle(AgentPalette.muted).padding(.bottom, 12)
                Button {
                    voice.stop(); model.draft = "Remind me to "; composerFocused = true
                } label: { auraSuggestion("Remember something for me", symbol: "bell") }
                .buttonStyle(.plain)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    auraSuggestion("Help with what's on my screen", symbol: "viewfinder")
                }
                .buttonStyle(.plain).disabled(voice.isRecording || voice.isStarting)
            }
        }
        .padding(.bottom, 8)
    }

    private func auraSuggestion(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(AgentPalette.accent).frame(width: 18)
            Text(title).font(.subheadline).foregroundStyle(.primary)
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(AgentPalette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .overlay(alignment: .bottom) { AgentPalette.line.opacity(0.5).frame(height: 0.5) }
        .contentShape(Rectangle())
    }

    private var composer: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                if let data = model.attachedImageData, let image = UIImage(data: data) {
                    HStack(spacing: 10) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screenshot attached").font(.subheadline.weight(.medium))
                            Text("Text is read on your device").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.attachImage(nil) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove screenshot")
                    }
                    .padding(8)
                    .background(AgentPalette.canvas, in: RoundedRectangle(cornerRadius: 12))
                }
                TextField(inputLocked ? "Finish this step to continue" : "Ask anything, or just talk…", text: $model.draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .disabled(inputLocked || voice.isRecording || voice.isStarting)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .frame(minHeight: 54)
                    .accessibilityLabel("Message hitapp")

                HStack(spacing: 2) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "plus").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Attach screenshot")
                    .disabled(inputLocked || voice.isRecording || voice.isStarting)
                    Text(voice.isStarting ? "Getting ready…" : voice.isRecording ? "Listening · tap to stop" : "Text, voice, or a screenshot")
                        .font(.system(size: 11)).foregroundStyle(AgentPalette.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Button {
                        composerFocused = false
                        if voice.isRecording || voice.isStarting { voice.stop() }
                        else { beginDictation() }
                    } label: {
                        Image(systemName: voice.isRecording ? "stop.circle" : "mic")
                            .font(.system(size: 17))
                            .foregroundStyle(voice.isRecording ? Color.red : AgentPalette.muted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(voice.isRecording || voice.isStarting ? "Stop dictation" : "Dictate request")
                    .disabled(inputLocked)
                    Button {
                        if model.isWorking { model.stop() }
                        else {
                            voice.stop()
                            composerFocused = false
                            model.send()
                        }
                    } label: {
                        Image(systemName: model.isWorking ? "stop.fill" : "arrow.up")
                            .font(.headline)
                            .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.13))
                            .frame(width: 44, height: 44)
                            .background(AgentPalette.action, in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.4), lineWidth: 0.75))
                            .opacity(model.isWorking || model.canSend ? 1 : 0.5)
                    }
                    .disabled(!model.isWorking && (!model.canSend || voice.isRecording || voice.isStarting))
                    .accessibilityLabel(model.isWorking ? "Stop" : "Send")
                }
                .foregroundStyle(.primary)
            }
            .padding(12)
            .background(AgentPalette.composer, in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(AgentPalette.accent.opacity(0.3), lineWidth: 1))
            .shadow(color: AgentPalette.accent.opacity(0.05), radius: 18, x: 0, y: -4)

            if !composerFocused {
                Button { showingConnections = true } label: {
                    HStack(spacing: 7) {
                        Circle().fill(tapp.connected ? AgentPalette.mint : AgentPalette.muted).frame(width: 5, height: 5)
                        Text(voice.isRecording ? "Dictate, review, then send" : connectionDescription)
                            .font(.system(size: 11)).foregroundStyle(AgentPalette.muted)
                    }.frame(minHeight: 28)
                }.buttonStyle(.plain).accessibilityLabel("Connections. " + connectionDescription)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .background(AgentPalette.canvas.opacity(0.95))
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo("conversation-end", anchor: .bottom)
        }
    }

    private func handleShortcutEntry() {
        guard scenePhase == .active, launch.consumeComposeRequest() else { return }
        let wasPresenting = showingSettings || showingConnections || showingScreenControl || showingActionButton
        awaitingShortcutFocus = true
        if wasPresenting { composerFocused = false }
        showingSettings = false
        showingConnections = false
        showingScreenControl = false
        showingActionButton = false
        // Never discard a draft, interrupt a running action, or bypass an approval.
        if !wasPresenting { completeShortcutEntry() }
    }

    private func completeShortcutEntry() {
        guard awaitingShortcutFocus, !inputLocked else { return }
        awaitingShortcutFocus = false
        TappCursorModel.shared.wake()
        composerFocused = true
    }

    private func beginDictation() {
        guard !inputLocked, !voice.isRecording, !voice.isStarting else { return }
        composerFocused = false
        dictationPrefix = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        voice.start()
    }
}
