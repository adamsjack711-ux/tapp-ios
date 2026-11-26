import Foundation

/// Best-effort local visual evidence, not an app identity or permission signal.
public struct HomeIndicatorObservation: Equatable, Sendable {
    public let centerX: Double
    public let centerY: Double
    public let width: Double
    public let height: Double
}

public enum HomeIndicatorRecognizer {
    /// Top-to-bottom grayscale pixels from a fresh portrait display capture.
    /// Requires one centered, thin, contrasting bar near the physical bottom.
    /// Missing/hidden/ambiguous indicators fail closed; no OCR label is guessed.
    public static func locate(pixels: [UInt8], width: Int, height: Int) -> HomeIndicatorObservation? {
        guard (100...1024).contains(width), height > width, height <= 4096,
              pixels.count == width * height else { return nil }
        struct Run { let y: Int; let left: Int; let right: Int }
        var groups: [[Run]] = []
        for y in Int(Double(height) * 0.95)..<Int(Double(height) * 0.995) {
            let offset = y * width
            let leftBackground = Int(pixels[offset + width / 10])
            let rightBackground = Int(pixels[offset + width * 9 / 10])
            guard abs(leftBackground - rightBackground) <= 30 else { continue }
            let background = (leftBackground + rightBackground) / 2
            let center = width / 2
            let sign = Int(pixels[offset + center]) >= background ? 1 : -1
            func contrasts(_ x: Int) -> Bool { (Int(pixels[offset + x]) - background) * sign >= 60 }
            guard contrasts(center) else { continue }
            var left = center, right = center
            while left > 0, contrasts(left - 1) { left -= 1 }
            while right + 1 < width, contrasts(right + 1) { right += 1 }
            let span = Double(right - left + 1) / Double(width)
            guard (0.20...0.50).contains(span), abs(Double(left + right) / 2 / Double(width) - 0.5) < 0.035 else { continue }
            let run = Run(y: y, left: left, right: right)
            if let last = groups.last?.last, y == last.y + 1,
               abs(left - last.left) <= 4, abs(right - last.right) <= 4 {
                groups[groups.count - 1].append(run)
            } else { groups.append([run]) }
        }
        let candidates = groups.compactMap { rows -> HomeIndicatorObservation? in
            guard let first = rows.first, let last = rows.last,
                  rows.count >= max(2, height / 1000), rows.count <= max(4, height / 100),
                  first.y >= 2, last.y + 2 < height else { return nil }
            let center = width / 2
            let bar = Int(pixels[((first.y + last.y) / 2) * width + center])
            let above = Int(pixels[(first.y - 2) * width + center])
            let below = Int(pixels[(last.y + 2) * width + center])
            guard abs(bar - above) >= 60, abs(bar - below) >= 60, abs(above - below) <= 40 else { return nil }
            let left = rows.map(\.left).min()!, right = rows.map(\.right).max()!
            return HomeIndicatorObservation(centerX: Double(left + right + 1) / 2 / Double(width),
                centerY: Double(first.y + last.y + 1) / 2 / Double(height),
                width: Double(right - left + 1) / Double(width), height: Double(rows.count) / Double(height))
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

public enum HomeNavigationAction: String, CaseIterable, Sendable {
    case home = "go_home", appSwitcher = "app_switcher"
    case pageLeft = "home_page_left", pageRight = "home_page_right"
    case openSettings = "open_settings"

    /// First explicit app-launch target. No model-supplied bundle IDs or URLs.
    public var launchBundleID: String? {
        self == .openSettings ? "com.apple.Preferences" : nil
    }

    /// Home uses a fixed system button event, including the first step of page
    /// navigation. App Switcher uses two fixed Home events.
    public var requiresBottomEdgeCoordinates: Bool { false }

    public var title: String {
        switch self {
        case .home: "Return to Home"
        case .appSwitcher: "Open App Switcher"
        case .pageLeft: "Go Home, then swipe one page left"
        case .pageRight: "Go Home, then swipe one page right"
        case .openSettings: "Open Settings"
        }
    }

    /// Exact navigation commands only; questions, compound requests and screen
    /// content cannot turn into an implicit command. No model is involved.
    public static func directCommand(_ text: String) -> Self? {
        let value = IPhoneNavigationLanguage.normalizedCommand(text)
        switch value {
        case "home", "go home", "return home", "return to home", "go back home", "take me home", "take me to the home screen", "go to the home screen", "show the home screen": return .home
        case "open app switcher", "open the app switcher", "show app switcher", "show the app switcher", "show my open apps", "show recent apps", "show running apps", "switch apps": return .appSwitcher
        case "swipe one home page left", "swipe one home screen page left", "next home page", "next home screen page": return .pageLeft
        case "swipe one home page right", "swipe one home screen page right", "previous home page", "previous home screen page": return .pageRight
        case "open settings", "launch settings", "take me to settings", "go to settings": return .openSettings
        default: return nil
        }
    }
}

/// One explicitly started, bounded navigation session. In-memory only, not a
/// general phone-control approval. Monotonic time prevents wall-clock changes
/// extending it, and attempts consume capacity even when input fails.
public struct HomeNavigationSession: Sendable {
    public static let lifetime: Double = 300
    public static let maximumAttempts = 10
    public private(set) var remainingAttempts = 0
    private var startedAt: Double?
    public init() {}
    public mutating func start(nowUptime: Double) {
        guard nowUptime.isFinite, nowUptime >= 0 else { stop(); return }
        startedAt = nowUptime; remainingAttempts = Self.maximumAttempts
    }
    public func isActive(nowUptime: Double) -> Bool {
        guard let startedAt, nowUptime.isFinite, remainingAttempts > 0 else { return false }
        return nowUptime >= startedAt && nowUptime - startedAt < Self.lifetime
    }
    public mutating func consume(nowUptime: Double) -> Bool {
        guard isActive(nowUptime: nowUptime) else { stop(); return false }
        remainingAttempts -= 1
        return true
    }
    public mutating func stop() { startedAt = nil; remainingAttempts = 0 }
}

public protocol HomeNavigationDevice: Sendable {
    func navigate(_ action: HomeNavigationAction, operationID: UUID) async throws -> String
    func cancel(operationID: UUID) async
}

/// Separate from app-scoped screen tools. No coordinates, app selection,
/// dismissal of cards, unlocks or arbitrary system gestures are accepted.
public struct HomeNavigationTool: AgentTool {
    // Navigation already ends the turn by policy. Return the same dispatch report
    // as the exact-command path without another model request to paraphrase it.
    public var returnsResultDirectly: Bool { true }

    /// Model guidance only. The device still enforces the persisted scope.
    public static func configurationContext(enabled: Bool, standingAccess: Bool = false) -> String {
        if enabled {
            if standingAccess {
                return "Separate Home navigation and Settings launch (phone_navigate) is ENABLED under the owner's standing authorization, independently of app-scoped screen_* tools. Execute one requested Home/App Switcher/Home-page/Open Settings action without asking for permission again, then stop. Open Settings only launches Settings; it does not change any setting. No screen_read needed. Do not ask to start a session."
            }
            return "Separate Home navigation and Settings launch (phone_navigate) is ENABLED, independently of app-scoped screen_* tools. For a Home, App Switcher, Home-page or Open Settings request, propose exactly one matching phone_navigate action and wait for approval. Open Settings is launch-only; it cannot change settings or open another app. Do not ask to enable app-scoped Screen Control or call screen_read first. Enabled is permission to propose, not permission to execute."
        }
        return "Separate navigation and Settings launch (phone_navigate) is DISABLED by the user. Explain that they can re-enable navigation in Screen Control. Never substitute screen_swipe."
    }

    public let requiresApproval: Bool
    private let device: any HomeNavigationDevice
    public init(device: any HomeNavigationDevice, requiresApproval: Bool = true) {
        self.device = device; self.requiresApproval = requiresApproval
    }
    public var definition: ToolDefinition {
        .init(name: "phone_navigate",
              description: "One separately enabled, approved operation from hitapp: return Home, open App Switcher, go Home then swipe one page left/right, or open Settings. Settings is the only launch target; opening it does not authorize changing settings. Leaves the phone at its destination. No app cards are tapped or closed. No screen_read needed. Outcome image stays local; do not claim visual success from dispatch.",
              parameters: ["type": .string("object"), "properties": .object([
                "action": .object(["type": .string("string"), "enum": .array(HomeNavigationAction.allCases.map { .string($0.rawValue) })])
              ]), "required": .array([.string("action")]), "additionalProperties": .bool(false)])
    }
    public func approvalSummary(arguments: [String: JSONValue]) -> PendingApproval {
        let action = arguments["action"]?.stringValue.flatMap(HomeNavigationAction.init(rawValue:))
        return .init(id: "", toolName: definition.name, title: action?.title ?? "Invalid navigation request",
                     explanation: "Experimental native navigation. Starts from hitapp, then leaves the phone at the destination. Open Settings launches that app only; it never changes a setting. Home-page actions first return Home, then send one sideways swipe; at an end page this may reveal widgets or App Library. A local result capture may contain app previews; neither its pixels nor text go to the model. No clicks, app closing or XCTest. Keep the unlocked phone untouched. Reopen hitapp yourself to see the result; no automatic retry.")
    }
    public func execute(arguments: [String: JSONValue]) async throws -> String {
        guard Set(arguments.keys) == ["action"], let raw = arguments["action"]?.stringValue,
              let action = HomeNavigationAction(rawValue: raw) else { throw ScreenControlError.invalidArguments }
        let id = UUID(), device = device
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await device.navigate(action, operationID: id)
        } onCancel: {
            Task { await device.cancel(operationID: id) }
        }
    }
}


/// Vocabulary for navigation requests, not an additional permission or input API.
/// Only the human chat request is classified. Screen/OCR content never enters here.
public enum IPhoneNavigationLanguage {
    public enum Intent: Equatable, Sendable {
        case swipe(String), back, dismissKeyboard, openApp(String), help, unsupported(String)
    }

    public static func normalizedCommand(_ text: String) -> String {
        var value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for _ in 0..<4 {
            if let prefix = ["hey tapp, ", "hey tapp ", "tapp, ", "tapp: ", "tapp ", "can you ", "could you ", "would you ", "please "].first(where: { value.hasPrefix($0) }) {
                value = String(value.dropFirst(prefix.count))
            } else { break }
        }
        return value
    }

    public static func intent(_ text: String) -> Intent? {
        let value = normalizedCommand(text)
        switch value {
        // Scroll names the content direction; swipe names the finger direction.
        case "scroll down", "scroll down a bit", "scroll down one page", "page down": return .swipe("up")
        case "scroll up", "scroll up a bit", "scroll up one page", "page up": return .swipe("down")
        case "scroll right": return .swipe("left")
        case "scroll left": return .swipe("right")
        case "swipe up": return .swipe("up")
        case "swipe down": return .swipe("down")
        case "swipe left": return .swipe("left")
        case "swipe right": return .swipe("right")
        case "back", "go back", "go back one page", "previous screen", "back one screen": return .back
        case "hide keyboard", "hide the keyboard", "dismiss keyboard", "dismiss the keyboard": return .dismissKeyboard
        case "navigation help", "show navigation commands", "what navigation commands do you understand", "what can you navigate": return .help
        case "open safari", "launch safari": return .openApp("com.apple.mobilesafari")
        case "open maps", "launch maps": return .openApp("com.apple.Maps")
        case "open photos", "launch photos": return .openApp("com.apple.mobileslideshow")
        case "open camera", "launch camera": return .openApp("com.apple.camera")
        case "open calendar", "launch calendar": return .openApp("com.apple.mobilecal")
        case "open notes", "launch notes": return .openApp("com.apple.mobilenotes")
        case "open mail", "launch mail": return .openApp("com.apple.mobilemail")
        case "open messages", "launch messages": return .openApp("com.apple.MobileSMS")
        case "open control center", "show control center", "open control centre", "show control centre":
            return .unsupported("Control Centre gestures are not implemented yet. Swipe down from the top-right corner yourself.")
        case "open notification center", "show notification center", "open notification centre", "show notifications":
            return .unsupported("Notification Centre gestures are not implemented yet. Swipe down from the top-left edge yourself.")
        case "open spotlight", "show spotlight", "search my iphone":
            return .unsupported("Spotlight navigation is not implemented yet. Go Home, then swipe down in the middle of the Home Screen yourself.")
        case "switch to the previous app", "switch to the last app", "go to the last app":
            return .unsupported("Switching directly to the last app is not implemented yet. Say ‘show my open apps’ to open App Switcher, then choose the app yourself.")
        case "close all apps", "close this app", "close an app", "close app", "force quit this app", "force close this app":
            return .unsupported("Name the app to close, for example ‘close Tapp Click Test’. Tapp checks its card before swiping it up. Closing can discard unsaved work; unnamed or all-app closing is not supported.")
        case "lock my phone", "lock the phone", "lock screen", "unlock my phone", "unlock the phone":
            return .unsupported("Tapp cannot lock or unlock your phone. Use the side button and your normal unlock method.")
        case "zoom in", "zoom out", "pinch to zoom", "rotate the screen", "open siri", "start siri":
            return .unsupported("That gesture or system control is not implemented yet. Use the phone’s controls for this step.")
        default: return nil
        }
    }

    public static let help = """
    Try ‘Tapp, take me Home’, ‘show my open apps’, ‘next Home Screen page’, ‘previous Home Screen page’, or ‘open Settings’.
    In your selected screen-control app, I also understand ‘go back’, ‘scroll down/up/left/right’, ‘swipe up/down/left/right’, ‘hide the keyboard’, and requests to tap or point at a visible control. These need a fresh screen read; missing or ambiguous controls stop the action. Scroll describes the content you want to reveal; swipe describes your finger’s direction.
    Opening another named app requires that app to be selected in Screen Control. Try ‘swipe through apps’, ‘previous app card’, ‘reopen Tapp Click Test’, or ‘close Tapp Click Test’. Closing requires an explicit app name and can discard unsaved work. Tapp checks screenshots between gestures. Control Centre, Notification Centre, Spotlight, direct last-app switching, pinch/zoom, screen rotation, Siri and lock/unlock are not implemented yet. Requests to change settings are separate from navigation.
    """

    public static func modelHint(for intent: Intent) -> String {
        switch intent {
        case .swipe(let direction):
            return "Navigation meaning: one screen_swipe with finger direction \(direction) inside the configured app only. First screen_read, then use its current observation_id. Do not replace this with a Home-page gesture. After one swipe inspect the result and stop."
        case .back:
            return "Navigation meaning: one level back inside the configured app. First screen_read. iPhone has no universal Back button. Use only a uniquely observed navigation-back label whose purpose is clear; do not invent a Back label, use Home, or guess an edge-swipe. If no reliable back control is observed, explain and stop."
        case .dismissKeyboard:
            return "Navigation meaning: dismiss the keyboard inside the configured app. First screen_read. Use an observed keyboard-dismiss control only. Done, Return, Send, Save and Submit may perform actions; do not assume they merely hide the keyboard. If no unambiguous dismiss control is observed, stop and explain."
        case .openApp(let bundle):
            return "Navigation meaning: open app \(bundle). Only if it exactly matches the configured allowed app and screen control is enabled, use screen_read for that bundle to open and read it. Otherwise explain that the user must select that app in Screen Control; do not change the saved scope, guess URL schemes, or substitute Settings."
        case .help, .unsupported: return ""
        }
    }
}

/// Exact human-entered gestures that need no model interpretation. Coordinates
/// and freshness remain owned by the native controller, never by this parser.
public enum LocalScreenCommand: Equatable, Sendable {
    case swipe(String), tap(String), point(String)

    public var action: ScreenAction {
        switch self {
        case .swipe: .swipe
        case .tap: .tap
        case .point: .point
        }
    }

    public static func parse(_ text: String) -> Self? {
        guard text.count <= 500, !text.contains(where: \.isNewline) else { return nil }
        if case .swipe(let direction) = IPhoneNavigationLanguage.intent(text) {
            return .swipe(direction)
        }
        let value = IPhoneNavigationLanguage.normalizedCommand(text)
        // Compound requests need interpretation, even when their first verb is familiar.
        guard !value.contains(" and "), !value.contains(" then "), !value.contains(";") else { return nil }
        // This is the same single-label highlight as "point to", not a navigation plan.
        // Only a unique label in a fresh observation can be used by execute().
        let showPrefix = "show me where "
        if value.hasPrefix(showPrefix), value.hasSuffix(" is") {
            let label = String(value.dropFirst(showPrefix.count).dropLast(3))
                .trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, label.count <= 300 else { return nil }
            return .point(label)
        }
        for prefix in ["point to ", "highlight ", "tap ", "click "] where value.hasPrefix(prefix) {
            let label = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, label.count <= 300 else { return nil }
            return prefix == "tap " || prefix == "click " ? .tap(label) : .point(label)
        }
        return nil
    }

    /// Read locally, resolve one unique OCR label, then perform exactly one action.
    /// Errors propagate without model fallback or replay of possibly completed input.
    public func execute(bundleID: String, controller: any ScreenActionController) async throws -> ScreenResult {
        try Task.checkCancellation()
        let observation = try await controller.perform(.read,
            arguments: ["bundle_id": .string(bundleID)], includeScreenshot: false)
        try Task.checkCancellation()
        guard observation.bundleID == bundleID else { throw ScreenControlError.wrongApp }
        var arguments: [String: JSONValue] = [
            "bundle_id": .string(bundleID), "observation_id": .string(observation.observationID)
        ]
        switch self {
        case .swipe(let direction):
            arguments["direction"] = .string(direction)
        case .tap(let label), .point(let label):
            let matches = observation.text.components(separatedBy: "\n").filter {
                $0.caseInsensitiveCompare(label) == .orderedSame
            }
            guard matches.count == 1, let observedLabel = matches.first else { throw ScreenControlError.ambiguousElement }
            arguments["label"] = .string(observedLabel)
            arguments["element_type"] = .string("StaticText")
        }
        try Task.checkCancellation()
        let result = try await controller.perform(action, arguments: arguments, includeScreenshot: true)
        try Task.checkCancellation()
        return result
    }
}

public enum AppSwitcherRequest: Equatable, Sendable {
    case show, browseLeft, browseRight, close(String), open(String)

    public static func directCommand(_ text: String) -> Self? {
        let text = IPhoneNavigationLanguage.normalizedCommand(text)
        switch text {
        case "show my open apps", "open app switcher", "open the app switcher", "show app switcher", "show the app switcher": return .show
        case "swipe through apps", "swipe through my apps", "next app card", "show the next app", "swipe right through apps", "swipe right in app switcher": return .browseRight
        case "previous app card", "show the previous app", "swipe left through apps", "swipe left in app switcher": return .browseLeft
        default: break
        }
        if HomeNavigationAction.directCommand(text) != nil { return nil }
        for prefix in ["open running app ", "reopen ", "switch to "] where text.hasPrefix(prefix) {
            let name = String(text.dropFirst(prefix.count))
            guard validName(name) else { return nil }
            return .open(name)
        }
        for prefix in ["close app ", "close ", "force quit "] where text.hasPrefix(prefix) {
            let name = String(text.dropFirst(prefix.count))
            guard validName(name) else { return nil }
            return .close(name)
        }
        return nil
    }

    /// A short continuation is meaningful only after an explicit switcher action.
    public static func continuation(_ text:String) -> Self? {
        switch IPhoneNavigationLanguage.normalizedCommand(text) {
        case "next", "next app", "right", "swipe right": .browseRight
        case "previous", "previous app", "left", "swipe left", "back": .browseLeft
        default: nil
        }
    }

    /// Compile every step before starting; never execute a supported prefix of
    /// an unrecognized long request. No unbounded repeats or unnamed closes.
    public static func plan(_ text:String) -> [Self]? {
        var value = IPhoneNavigationLanguage.normalizedCommand(text)
        value = value.replacingOccurrences(of:" and then ",with:" then ")
            .replacingOccurrences(of:", then ",with:" then ")
            .replacingOccurrences(of:", ",with:" then ")
        guard value.contains(" then ") else { return nil }
        let parts = value.components(separatedBy:" then ")
        guard (2...8).contains(parts.count) else { return nil }
        var result:[Self] = []
        for part in parts {
            let twice = part.hasSuffix(" twice")
            let command = twice ? String(part.dropLast(6)) : part
            guard let action = directCommand(command) ?? continuation(command),
                  !twice || action == .browseLeft || action == .browseRight else { return nil }
            result.append(action)
            if twice { result.append(action) }
        }
        return result.count <= 8 ? result : nil
    }

    public static func validName(_ name: String) -> Bool {
        let value = name.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 80 &&
            !["this app", "the app", "an app", "app", "all apps", "all", "hitapp", "tapp", "pocketagent"].contains(value) &&
            ![" and ", " then ", "\n", "?", ";"].contains(where: value.contains)
    }

    public var action: String {
        switch self { case .show: "show"; case .browseLeft: "left"; case .browseRight: "right"; case .close: "close"; case .open: "open" }
    }
    public var appName: String? { switch self { case .close(let name), .open(let name): name; default: nil } }

    public static func decode(_ arguments: [String:JSONValue]) throws -> Self {
        switch arguments["action"]?.stringValue {
        case "show" where Set(arguments.keys) == ["action"]: return .show
        case "left" where Set(arguments.keys) == ["action"]: return .browseLeft
        case "right" where Set(arguments.keys) == ["action"]: return .browseRight
        case "close", "open":
            guard Set(arguments.keys) == ["action","app_name"], let name = arguments["app_name"]?.stringValue, validName(name) else { throw ScreenControlError.invalidArguments }
            return arguments["action"]?.stringValue == "close" ? .close(name) : .open(name)
        default: throw ScreenControlError.invalidArguments
        }
    }

    /// Only a fully readable, unique app header above a central card qualifies.
    /// This is paired with a freshly opened switcher and inactive app state.
    public static func card(named name: String, in frame: NativeScreenFrame) throws -> NativeScreenText {
        guard !frame.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
        let matches = frame.items.filter {
            $0.label.caseInsensitiveCompare(name) == .orderedSame &&
            $0.y >= 0.10 && $0.y < 0.17 && $0.width < 0.7 &&
            (0.20...0.80).contains($0.x + $0.width/2)
        }
        guard matches.count == 1 else { throw ScreenControlError.ambiguousElement }
        return matches[0]
    }
}

public protocol AppSwitcherDevice: Sendable {
    func controlSwitcher(_ request:AppSwitcherRequest, operationID:UUID) async throws -> String
    func cancel(operationID:UUID) async
}

public struct AppSwitcherTool: AgentTool {
    private let device:any AppSwitcherDevice
    public let requiresApproval: Bool
    public init(device:any AppSwitcherDevice, requiresApproval:Bool = true) {
        self.device = device
        self.requiresApproval = requiresApproval
    }
    public var definition:ToolDefinition {
        .init(name:"app_switcher",description:"Open App Switcher and drag one card left/right, or find and open or swipe up one explicitly named installed app card. Fresh screenshots are checked after every drag and immediately before closing. Closing may discard unsaved work. Never close an unspecified app, hitapp or all apps. Opening uses one brief held selection; closing uses a continuous upward drag. No input retries.",parameters:["type":.string("object"),"properties":.object([
            "action":.object(["type":.string("string"),"enum":.array([.string("show"),.string("left"),.string("right"),.string("close"),.string("open")])]),
            "app_name":.object(["type":.string("string"),"description":.string("Exact installed app name explicitly requested by the user; required for open or close.")])
        ]),"required":.array([.string("action")]),"additionalProperties":.bool(false)])
    }
    public func approvalSummary(arguments:[String:JSONValue]) -> PendingApproval {
        let request = try? AppSwitcherRequest.decode(arguments)
        return .init(id:"",toolName:definition.name,title:request?.appName.map { "\(request?.action == "open" ? "Open" : "Close") \($0)" } ?? "Swipe through App Switcher",explanation:"Uses a continuous press, drag and release. A named app may lose unsaved work when closed. Screenshots are checked locally between steps; no other app is closed.")
    }
    public func execute(arguments:[String:JSONValue]) async throws -> String {
        let request = try AppSwitcherRequest.decode(arguments), id = UUID(), device = device
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await device.controlSwitcher(request,operationID:id)
        } onCancel: { Task { await device.cancel(operationID:id) } }
    }
}
