import SwiftUI
import UIKit

enum AgentPalette {
    static let accent = Color(red: 0.70, green: 0.62, blue: 0.94)
    static let canvas = Color(red: 0.035, green: 0.035, blue: 0.055)
    static let surface = Color(red: 0.085, green: 0.078, blue: 0.12)
    static let muted = Color(red: 0.69, green: 0.66, blue: 0.75)
    static let line = Color.white.opacity(0.12)
    static let mint = Color(red: 0.66, green: 0.86, blue: 0.79)
    static let composer = LinearGradient(colors: [Color(red: 0.125, green: 0.118, blue: 0.176), Color(red: 0.063, green: 0.063, blue: 0.094)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let action = LinearGradient(colors: [Color(red: 0.82, green: 0.73, blue: 0.98), Color(red: 0.54, green: 0.47, blue: 0.86), Color(red: 0.34, green: 0.50, blue: 0.66)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct AuraBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                AgentPalette.canvas
                Ellipse().fill(Color(red: 0.44, green: 0.24, blue: 0.70).opacity(0.30))
                    .frame(width: geometry.size.width * 0.95, height: 270).blur(radius: 65)
                    .offset(x: -100, y: 160)
                Ellipse().fill(Color(red: 0.16, green: 0.36, blue: 0.66).opacity(0.28))
                    .frame(width: geometry.size.width * 0.85, height: 270).blur(radius: 65)
                    .offset(x: 100, y: 70)
                Ellipse().fill(Color(red: 0.71, green: 0.31, blue: 0.49).opacity(0.13))
                    .frame(width: 260, height: 200).blur(radius: 65).offset(x: 70, y: 270)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct AuraCursorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [.init(x: 0.07, y: 0.02), .init(x: 0.94, y: 0.57), .init(x: 0.60, y: 0.64), .init(x: 0.79, y: 0.94), .init(x: 0.59, y: 1), .init(x: 0.40, y: 0.70), .init(x: 0.14, y: 0.92)]
        path.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        path.closeSubpath()
        return path
    }
}

/// Aura's in-app character. Only the speech bubble animates; this does not
/// change the paired system cursor or its accepted navigation trajectory.
struct AuraCursor: View {
    var size: CGFloat = 24
    var working = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var began = Date.distantPast
    @State private var playing = false
    @State private var replay = 0

    var body: some View {
        Button { replay += 1 } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || reduceMotion)) { context in
                let elapsed = context.date.timeIntervalSince(began)
                let pop = reduceMotion || !playing ? 1 : min(1, max(0, elapsed / 0.48))
                let scale = pop >= 1 ? 1 : 1 - exp(-7 * pop) * cos(10 * pop)
                ZStack {
                    ZStack {
                        AuraCursorShape().fill(LinearGradient(colors: [Color(red: 0.88, green: 0.93, blue: 1), Color(red: 0.45, green: 0.52, blue: 0.92), Color(red: 0.27, green: 0.23, blue: 0.57)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        AuraCursorShape().stroke(Color.white.opacity(0.65), lineWidth: 0.75)
                        HStack(spacing: size * 0.10) {
                            Capsule().frame(width: size * 0.085, height: size * 0.16)
                            Capsule().frame(width: size * 0.085, height: size * 0.16)
                        }
                        .foregroundStyle(Color(red: 0.15, green: 0.14, blue: 0.27))
                        .offset(x: -size * 0.07, y: -size * 0.01)
                    }
                    .frame(width: size, height: size * 1.12)
                    .rotationEffect(.degrees(-6)).offset(y: 7)
                    .shadow(color: AgentPalette.accent.opacity(0.25), radius: 6)
                    HStack(spacing: 3) {
                        ForEach(0..<3) { index in
                            let phase = max(0, elapsed - 0.35 - Double(index) * 0.11)
                            let bounce = playing && !reduceMotion && phase > 0 && phase < 1.95 ? max(0, sin(phase / 0.65 * .pi * 2)) * 2 : 0
                            Circle().fill(Color(red: 0.87, green: 0.84, blue: 0.96)).frame(width: 3, height: 3).offset(y: -bounce)
                        }
                    }
                    .frame(width: 31, height: 19)
                    .background(LinearGradient(colors: [Color(red: 0.29, green: 0.25, blue: 0.37), Color(red: 0.17, green: 0.15, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(AgentPalette.accent.opacity(0.4), lineWidth: 1))
                    .overlay(alignment: .bottomLeading) {
                        Rectangle().fill(Color(red: 0.19, green: 0.16, blue: 0.25)).frame(width: 5, height: 5).rotationEffect(.degrees(45)).offset(x: 7, y: 2)
                    }
                    .scaleEffect(scale, anchor: .bottomLeading).offset(x: 5, y: -size * 0.55)
                }
                .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(working ? "Tapp is working. Replay speech bubble" : "Tapp. Animate speech bubble")
        .onChange(of: working) { _, active in if active { replay += 1 } }
        .onAppear { if working { replay += 1 } }
        .task(id: replay) {
            guard replay > 0, !reduceMotion else { playing = false; return }
            began = .now; playing = true
            do { try await Task.sleep(for: .milliseconds(2600)) } catch { return }
            playing = false
        }
    }
}

struct AgentMark: View {
    var size: CGFloat = 28
    var body: some View {
        AuraCursor(size: min(size, 28))
    }
}

struct ProviderPresentation {
    let baseURL: String
    let model: String
    var configured: Bool { !baseURL.isEmpty && !model.isEmpty }
    var local: Bool { URL(string: baseURL).map(OpenAICompatibleClient.isLoopback) ?? false }
    var name: String { model.isEmpty ? "Choose a model" : model }
    var symbol: String { !configured ? "cpu" : local ? "desktopcomputer" : "network" }
    var location: String {
        guard configured else { return "Demo mode" }
        #if targetEnvironment(simulator)
        return local ? "On your Mac" : "Remote provider"
        #else
        return local ? "Local endpoint" : "Remote provider"
        #endif
    }
}

struct StarterRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(AgentPalette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct StarterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(AgentPalette.surface.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(AgentPalette.line, lineWidth: 1))
    }
}

struct ConversationMessage: View {
    let item: AppModel.ChatItem
    var body: some View {
        switch item.speaker {
        case .user:
            HStack {
                Spacer(minLength: 36)
                Text(item.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 22))
            }
            .accessibilityLabel("You: \(item.text)")
        case .agent:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    AgentMark()
                    Text("hitapp").font(.footnote.weight(.semibold))
                }
                Text((try? AttributedString(markdown: item.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(item.text))
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .status:
            Label(item.text, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PendingActionCard: View {
    let approval: PendingApproval
    let approve: () -> Void
    let reject: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var actionTitle: String {
        switch approval.toolName {
        case "screen_read": return "Read screen"
        case "screen_point": return "Show me where"
        case "screen_tap": return "Approve tap"
        case "screen_hold": return "Hold once"
        case "screen_drag": return "Drag once"
        case "screen_swipe": return "Swipe once"
        case "screen_type": return "Append text"
        case "create_reminder": return "Create reminder"
        default: return "Approve action"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your approval needed").font(.subheadline.weight(.semibold))
                    Text("One action. Only with your say-so.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label(approval.toolName.hasPrefix("screen_") ? "SCREEN CONTROL" : approval.toolName == "create_reminder" ? "APPLE REMINDERS" : "PROPOSED ACTION",
                      systemImage: approval.toolName.hasPrefix("screen_") ? "hand.tap" : "checklist")
                    .font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                Text(approval.title).font(.title3.weight(.semibold))
                Text(approval.explanation).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Button(action: reject) {
                    Text("Cancel").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
                .background(AgentPalette.canvas, in: RoundedRectangle(cornerRadius: 13))
                Button(action: approve) {
                    Text(actionTitle).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(AgentPalette.accent, in: RoundedRectangle(cornerRadius: 13))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AgentPalette.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.orange.opacity(0.38), lineWidth: 1))
    }
}

struct WorkingCard: View {
    let title: String
    let detail: String
    let stop: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AuraCursor(size: 28, working: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Stop", role: .destructive, action: stop).font(.subheadline.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(16)
        .background(AgentPalette.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }
}

struct InlineErrorCard: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Couldn’t finish this request", systemImage: "exclamationmark.circle").font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Dismiss error")
            }
            .foregroundStyle(.red)
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text("Nothing is retried automatically.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ConnectionsView: View {
    @ObservedObject var model: AppModel
    let provider: ProviderPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var modelSettings = false
    @State private var screenSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(provider.name, systemImage: provider.symbol).font(.headline)
                    Text(provider.location).foregroundStyle(.secondary)
                    Label(model.lastModelResponseAt == nil ? "Not checked this session" : "Last response received",
                          systemImage: model.lastModelResponseAt == nil ? "circle.dashed" : "checkmark.circle")
                    if let date = model.lastModelResponseAt {
                        Text(date, style: .time).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Model settings") { modelSettings = true }.disabled(model.isWorking || model.pendingApproval != nil)
                } header: { Text("Language model") } footer: {
                    Text("A received response confirms that request only. This is not a continuous connection check.")
                }
                Section {
                    Label(model.screen.isEnabled ? "Supervised control enabled" : "Screen control is off", systemImage: "hand.tap")
                        .font(.headline)
                    Text(model.screen.isPaired ? "A runner key is saved. Connection is checked separately." : "No runner paired. A model connection doesn’t grant screen access.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Screen control setup") { screenSettings = true }
                } header: { Text("iPhone screen") } footer: {
                    Text("Requested Tapp gestures use your saved access without another approval card. You can stop control at any time.")
                }
            }
            .navigationTitle("Connections").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(AgentPalette.accent)
        .sheet(isPresented: $modelSettings) { SettingsView() }
        .sheet(isPresented: $screenSettings) { ScreenControlView(screen: model.screen).environmentObject(model) }
    }
}
