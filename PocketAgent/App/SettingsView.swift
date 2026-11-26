import SwiftUI
import AppIntents

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.baseURL) private var baseURL = ""
    @AppStorage(SettingsKeys.model) private var model = ""
    @AppStorage(SettingsKeys.homeWiFi) private var homeWiFi = true
    @State private var apiKey = KeychainStore.read(SettingsKeys.apiKey) ?? ""
    @State private var isTesting = false
    @State private var connectionResult: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var showingActionButton = false
    @State private var showingScreenControl = false
    @State private var showingBugReport = false

    private var isLocal: Bool {
        URL(string: baseURL).map(OpenAICompatibleClient.isLoopback) ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingActionButton = true
                    } label: {
                        Label("Action button", systemImage: "bolt.fill")
                    }
                } header: { Text("Quick access") } footer: {
                    Text("Ask hitapp from the Action button, Siri, or Shortcuts.")
                }
                Section {
                    Button { showingScreenControl = true } label: {
                        Label("Screen Control", systemImage: "hand.tap")
                    }
                } header: { Text("Optional features") } footer: {
                    Text("Off by default. Set up the developer-installed helper here, then explicitly enable control for one app. Chat works without it.")
                }
                #if targetEnvironment(simulator)
                Section {
                    Button("Use Ollama on this Mac", systemImage: "desktopcomputer") {
                        baseURL = SettingsKeys.ollamaBaseURL
                        model = SettingsKeys.ollamaModel
                        connectionResult = nil
                    }
                    .disabled(isTesting)
                    Text("gpt-oss:20b runs on your Mac. Keep Ollama running while you use the simulator. No API key is needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Local model")
                }
                #endif
                Section {
                    TextField("https://provider.example/v1", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Model name", text: $model)
                        .textInputAutocapitalization(.never)
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .disabled(isLocal)
                } header: {
                    Text("Model provider")
                } footer: {
                    Text(isLocal
                         ? "Localhost uses this device's loopback connection. In the simulator it reaches your Mac; on a physical iPhone it does not. Stored API keys are not sent to localhost."
                         : "Use an HTTPS OpenAI-compatible /v1 endpoint. Clear the URL and model name to use demo mode.")
                }
                .disabled(isTesting)

                if URL(string: baseURL)?.host == HomeWiFiModelTransport.serverName {
                    Section("Mac connection") {
                        Toggle("Use approved home Wi-Fi connection", isOn: $homeWiFi)
                        Text("Encrypted and authenticated. Keeps Ollama reachable while native screen control uses the local VPN. Your iPhone and Mac must be on the configured home Wi-Fi. Turn off to use Tailscale when screen control is stopped.").font(.footnote)
                    }.disabled(isTesting)
                }

                Section {
                    Button {
                        connectionResult = nil
                        isTesting = true
                        let client = ConfiguredModelClient.client(baseURL: baseURL, model: model, apiKey: apiKey, homeWiFi: homeWiFi)
                        connectionTask = Task { @MainActor in
                            defer { isTesting = false; connectionTask = nil }
                            do {
                                let reply = try await client.reply(to: [ModelMessage(role: .user, content: "Reply with exactly: Connected.")], tools: [])
                                guard !Task.isCancelled else { return }
                                connectionResult = reply.content.isEmpty ? "The model returned no answer." : "Model replied successfully."
                            } catch {
                                if !Task.isCancelled { connectionResult = error.localizedDescription }
                            }
                        }
                    } label: {
                        HStack {
                            Text(isTesting ? "Waiting for the model…" : "Test connection")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(isTesting || baseURL.isEmpty || model.isEmpty)
                    if let connectionResult {
                        Text(connectionResult).font(.footnote)
                    }
                } footer: {
                    Text("Sends a short test prompt to the selected model. The first local response can take longer while the model loads.")
                }

                Section {
                    Button { showingBugReport = true } label: {
                        Label("Report a bug", systemImage: "ladybug")
                    }
                    .disabled(!apiKey.hasPrefix("tapp_") || ResponsesModelClient.endpoint(baseURL: baseURL) == nil)
                } header: { Text("Help") } footer: {
                    Text("Send feedback using your Tapp beta connection. A Tapp access code is required.")
                }

                Section("Privacy") {
                    Label("API keys stay in Keychain", systemImage: "key.fill")
                    Label("Screen access is explicit and opt-in", systemImage: "photo.badge.checkmark")
                    Text("Approved screen tools send the target app's visible text to your model provider. Manual Screen Control previews stay on the device.")
                        .font(.footnote)
                    Label("Tapp uses your saved screen access", systemImage: "checkmark.shield.fill")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingActionButton) { ActionButtonSetupView() }
            .sheet(isPresented: $showingBugReport) {
                BugReportView(baseURL: baseURL, accessCode: apiKey)
            }
            .sheet(isPresented: $showingScreenControl) {
                ScreenControlView(screen: app.screen).environmentObject(app)
            }
            .onDisappear { connectionTask?.cancel() }
            .onChange(of: baseURL) { _, _ in
                connectionResult = nil
                apiKey = KeychainStore.read(SettingsKeys.apiKey) ?? ""
            }
            .onChange(of: model) { _, _ in connectionResult = nil }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if apiKey.isEmpty {
                            KeychainStore.delete(SettingsKeys.apiKey)
                        } else {
                            KeychainStore.save(apiKey, for: SettingsKeys.apiKey)
                        }
                        dismiss()
                    }
                }
            }
        }
        .tint(AgentPalette.accent)
    }
}

struct BugReportView: View {
    let baseURL: String
    let accessCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var includeDeviceInfo = true
    @State private var submissionID = UUID()
    @State private var submittedReport: TappBugReport?
    @State private var receipt: TappBugReportReceipt?
    @State private var isSending = false
    @State private var errorMessage: String?

    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "unknown") (\(info["CFBundleVersion"] as? String ?? "unknown"))"
    }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf16.count <= 120 &&
        !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && details.utf16.count <= 8000
    }

    var body: some View {
        NavigationStack {
            Form {
                if let receipt {
                    Section {
                        Label("Report sent", systemImage: "checkmark.circle.fill")
                        Text("Thanks for helping improve Tapp.")
                        Text("Reference: \(receipt.id)").font(.footnote).textSelection(.enabled)
                    }
                } else {
                    Section {
                        TextField("Short summary", text: $title)
                        TextField("What happened? What did you expect? How can we reproduce it?", text: $details, axis: .vertical)
                            .lineLimit(6...14)
                        Text("Title: \(title.utf16.count)/120 · Details: \(details.utf16.count)/8000")
                            .font(.caption).foregroundStyle(.secondary)
                    } header: { Text("Your report") } footer: {
                        Text("Please leave out passwords, access codes, and private information. Reports are kept for up to 30 days and removed if you delete your account.")
                    }
                    .disabled(isSending || submittedReport != nil)
                    Section {
                        Toggle("Include app and device info", isOn: $includeDeviceInfo)
                        if includeDeviceInfo {
                            Text("Tapp \(appVersion) · iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)")
                                .font(.footnote)
                        }
                    } footer: {
                        Text("Only this report and the information shown above are sent. Screenshots and conversations are not attached.")
                    }
                    .disabled(isSending || submittedReport != nil)
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                    Section {
                        Button(action: send) {
                            HStack {
                                Text(isSending ? "Sending…" : submittedReport == nil ? "Send report" : "Retry sending")
                                Spacer()
                                if isSending { ProgressView() }
                            }
                        }.disabled(isSending || !valid)
                        if submittedReport != nil && !isSending {
                            Text("Delivery couldn’t be confirmed. Retry sends the same report without creating a duplicate.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Report a bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(receipt == nil ? "Cancel" : "Done") { dismiss() }.disabled(isSending)
                }
            }
            .interactiveDismissDisabled(isSending)
        }.tint(AgentPalette.accent)
    }

    private func send() {
        guard valid, !isSending else { return }
        let report = submittedReport ?? TappBugReport(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: details.trimmingCharacters(in: .whitespacesAndNewlines),
            appVersion: includeDeviceInfo ? appVersion : nil,
            osVersion: includeDeviceInfo ? UIDevice.current.systemVersion : nil,
            deviceModel: includeDeviceInfo ? UIDevice.current.model : nil)
        submittedReport = report
        isSending = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSending = false }
            do {
                receipt = try await TappAccountClient(baseURL: baseURL, accessCode: accessCode)
                    .submitBugReport(report, submissionID: submissionID)
            } catch {
                errorMessage = error.localizedDescription
                // Validation/auth/rate errors confirm that nothing was saved; allow editing.
                if let backend = error as? TappBackendError, [400, 401, 413, 415, 429].contains(backend.status) {
                    submittedReport = nil
                }
            }
        }
    }
}

struct ActionButtonSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "bolt.fill")
                            .font(.title2).foregroundStyle(AgentPalette.accent)
                            .frame(width: 48, height: 48)
                            .background(AgentPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        Text("Your next request.\nOne shortcut away.").font(.title2.weight(.semibold))
                        Text("Pocket Voice uses iOS dictation and a compact system answer, without opening this app. Review your words before sending to your configured model. This voice surface answers questions; phone actions still need in-app approval.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    Button("Open the app composer", systemImage: "arrow.up.forward.app") {
                        Task {
                            _ = try? await SummonPocketAgentIntent().perform()
                            dismiss()
                        }
                    }
                }
                Section("On your iPhone") {
                    Label("Create a shortcut named Pocket Voice", systemImage: "1.circle")
                    Label("Add Dictate Text; choose stop listening On Tap", systemImage: "2.circle")
                    Label("Add Dictate to hitapp; Request = Dictated Text", systemImage: "3.circle")
                    Label("Add Show Result; display the model answer", systemImage: "4.circle")
                    Label("Settings → Action Button → Shortcut → Pocket Voice", systemImage: "5.circle")
                    Text("For Siri, say ‘Ask hitapp’. Only ‘Open hitapp’ opens the composer.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    ShortcutsLink()
                    Link("Apple’s Action button guide", destination: URL(string: "https://support.apple.com/guide/shortcuts/run-shortcuts-with-the-action-button-apdfea15680b/ios")!)
                } footer: {
                    Text("Do not add Open App or Open hitapp to Pocket Voice; those explicitly open the app. iOS owns the dictation UI and may ask for permission or an unlock. Its dictation privacy/language settings apply. Our in-app microphone is separate and remains on-device-only. The configured model still needs its connection (currently Mac Ollama).")
                }
            }
            .navigationTitle("Action button").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(AgentPalette.accent)
    }
}
