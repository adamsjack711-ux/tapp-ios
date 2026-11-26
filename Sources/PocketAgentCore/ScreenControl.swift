import CryptoKit
import Foundation

public enum ScreenControlError: LocalizedError, Equatable {
    case disabled, guideOnly, wrongApp, busy, invalidArguments, staleScreen, ambiguousElement, notTextInput, blockedByAlert

    public var errorDescription: String? {
        switch self {
        case .disabled: return "Screen control is off. Enable it explicitly in Screen Control."
        case .guideOnly: return "Guide me mode can read and point, but cannot tap, swipe or type. Choose Act automatically to allow those actions."
        case .wrongApp: return "This app is not the target you allowed in Screen Control, or it did not come to the foreground."
        case .busy: return "A screen operation is already running."
        case .invalidArguments: return "Invalid screen action. Use a known app, an exact visible label, and a supported gesture."
        case .staleScreen: return "The screen changed, expired, or has not been read. Read it again before approving an action. Nothing was tapped or typed."
        case .ambiguousElement: return "The control is missing, ambiguous or not fully visible. If the screen lists both a control and its text label, specify its observed element_type (for example Cell). Nothing was tapped or typed."
        case .notTextInput: return "The selected control is not a text field. Nothing was typed."
        case .blockedByAlert: return "A system alert covers the app. Handle it yourself before continuing."
        }
    }
}

public enum ScreenAction: String, CaseIterable, Sendable {
    case read = "screen_read"
    case point = "screen_point"
    case tap = "screen_tap"
    case hold = "screen_hold"
    case drag = "screen_drag"
    case swipe = "screen_swipe"
    case type = "screen_type"
}

public enum ScreenInteractionMode: String, CaseIterable, Sendable {
    case guide = "Guide me"
    case act = "Act automatically"
}

/// This personal build has the owner's standing authorization. These defaults
/// do not grant iOS permissions, create pairing identities, or connect a device.
/// Explicitly switching access off persists across launches and upgrades.
@MainActor
public struct ScreenControlAccessStore {
    private let defaults: UserDefaults
    private let prefix = "pocket.native.standingAccess.v1."
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var appEnabled: Bool {
        get { defaults.object(forKey: prefix + "app") == nil ? true : defaults.bool(forKey: prefix + "app") }
        nonmutating set { defaults.set(newValue, forKey: prefix + "app") }
    }
    public var navigationEnabled: Bool {
        get { defaults.object(forKey: prefix + "navigation") == nil ? true : defaults.bool(forKey: prefix + "navigation") }
        nonmutating set { defaults.set(newValue, forKey: prefix + "navigation") }
    }
    public var bundleID: String {
        get { defaults.string(forKey: prefix + "bundle") ?? "com.apple.Preferences" }
        nonmutating set { defaults.set(newValue, forKey: prefix + "bundle") }
    }
    public var mode: ScreenInteractionMode {
        get {
            guard let raw = defaults.string(forKey: prefix + "mode") else { return .act }
            return ScreenInteractionMode(rawValue: raw) ?? .guide
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: prefix + "mode") }
    }
}

/// Narrow, deterministic navigation exemptions, not a label-based promise that
/// arbitrary taps are safe. Unknown controls still get consequence-specific
/// review. The native controller separately verifies app, freshness and alerts.
public enum ScreenApprovalPolicy: Sendable {
    case everyOperation, standingAccess, requestedActions

    public func requiresApproval(action: ScreenAction, arguments: [String: JSONValue]) -> Bool {
        // Personal-build owner choice: submitting a request authorizes its
        // supported gestures. Scope, Guide mode, freshness and system-prompt
        // blocking remain enforced by the controller, independently of review.
        if self == .requestedActions { return action == .type }
        guard self == .standingAccess else { return true }
        switch action {
        case .read, .point, .swipe: return false
        case .type, .hold, .drag: return true
        case .tap:
            guard arguments["bundle_id"] == .string("com.apple.Preferences"),
                  let label = arguments["label"]?.stringValue else { return true }
            // Known Settings destination rows only: never switches, Save/Done,
            // Send, Delete, purchases, pairing, passwords or permission buttons.
            return !["Settings", "General", "About", "Accessibility", "Display & Brightness",
                     "Text Size", "Home Screen & App Library", "Battery", "Sounds & Haptics",
                     "Notifications", "Apps"].contains(label)
        }
    }
}

/// Normalized bounds supplied by a uniquely resolved control, never model-guessed coordinates.
/// These annotate a captured image in our own app, not a system-wide overlay.
public struct ScreenHighlight: Sendable, Equatable, Codable {
    public let label: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(label: String, element: [String: JSONValue], screenshot: [String: JSONValue]) throws {
        guard let x = element["x"]?.numberValue, let y = element["y"]?.numberValue,
              let width = element["width"]?.numberValue, let height = element["height"]?.numberValue,
              let screenWidth = screenshot["point_width"]?.numberValue,
              let screenHeight = screenshot["point_height"]?.numberValue,
              [x, y, width, height, screenWidth, screenHeight].allSatisfy(\.isFinite),
              x >= 0, y >= 0, width > 0, height > 0, screenWidth > 0, screenHeight > 0,
              x + width <= screenWidth, y + height <= screenHeight else {
            throw ScreenControlError.ambiguousElement
        }
        self.label = label
        self.x = x / screenWidth
        self.y = y / screenHeight
        self.width = width / screenWidth
        self.height = height / screenHeight
    }
}

public struct ScreenResult: Sendable, Codable {
    public let observationID: String
    public let bundleID: String
    public let text: String
    public let screenshot: Data?
    public let outcome: String
    public let returnWarning: String?
    public var highlight: ScreenHighlight? = nil
    public var capturedAt: Date = .now

    public var modelText: String {
        let object: [String: JSONValue] = [
            "observation_id": .string(observationID), "bundle_id": .string(bundleID),
            "outcome": .string(outcome), "untrusted_screen_text": .string(text),
            "pointed_label": highlight.map { .string($0.label) } ?? .null,
            "return_warning": returnWarning.map(JSONValue.string) ?? .null
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(object)) ?? Data(), encoding: .utf8) ?? ""
    }
}

/// One explicitly allowed app, one approved action, then return to hitapp.
/// No arbitrary RPC names, URL opening, sends, unlocks, or security settings API.
public protocol ScreenActionController: Sendable {
    func configure(enabled: Bool, allowedBundleID: String, mode: ScreenInteractionMode) async throws
    func disable() async
    func perform(_ action: ScreenAction, arguments: [String: JSONValue], includeScreenshot: Bool) async throws -> ScreenResult
}

public actor ScreenController: ScreenActionController {
    private struct Observation {
        let id: String
        let bundleID: String
        let fingerprint: Data
        let time: Date
    }

    private let rpc: any ScreenRPC
    private let returnBundleID: String
    private var enabled = false
    private var mode: ScreenInteractionMode = .guide
    private var allowedBundleID = "com.apple.Preferences"
    private var busy = false
    private var observation: Observation?

    public init(rpc: any ScreenRPC, returnBundleID: String) {
        self.rpc = rpc
        self.returnBundleID = returnBundleID
    }

    public func configure(enabled: Bool, allowedBundleID: String, mode: ScreenInteractionMode = .guide) throws {
        guard !busy else { throw ScreenControlError.busy }
        guard Self.validBundleID(allowedBundleID), allowedBundleID != returnBundleID,
              allowedBundleID != "com.apple.springboard" else { throw ScreenControlError.invalidArguments }
        self.enabled = enabled
        self.mode = mode
        self.allowedBundleID = allowedBundleID
        observation = nil
    }

    public func disable() {
        enabled = false
        observation = nil
    }

    public func perform(_ action: ScreenAction, arguments: [String: JSONValue],
                        includeScreenshot: Bool = false) async throws -> ScreenResult {
        guard action != .hold && action != .drag else { throw NativeScreenError.unsupportedGesture }
        guard enabled else { throw ScreenControlError.disabled }
        guard !busy else { throw ScreenControlError.busy }
        guard mode == .act || action == .read || action == .point else { throw ScreenControlError.guideOnly }
        let bundle = try validate(action, arguments)
        busy = true
        defer { busy = false }
        var activated = false
        do {
            let info = try await checkedCall("device_info")
            guard info["protocol_version"] == .number(1) else { throw ICTRLError.invalidResponse }
            // Mark before awaiting: a lost reply does not mean activation didn't happen.
            activated = true
            let activation = try await checkedCall("activate_app", ["bundle_id": .string(bundle)])
            try checkForeground(activation, bundle: bundle)

            var outcome = "Opened and read the app."
            var pointedElement: [String: JSONValue]?
            if action != .read {
                guard activation["relaunched"] != .bool(true), let last = observation,
                      arguments["observation_id"]?.stringValue == last.id, last.bundleID == bundle,
                      Date().timeIntervalSince(last.time) < 120 else { throw ScreenControlError.staleScreen }
                let current = try await readTree(bundle)
                guard fingerprint(current) == last.fingerprint else { throw ScreenControlError.staleScreen }
                // Consume before the write: errors/timeouts must never allow replaying this approval.
                observation = nil
                let response: [String: JSONValue]
                switch action {
                case .read: response = [:]
                case .point, .tap, .type:
                    var query: [String: JSONValue] = ["bundle_id": .string(bundle), "match": .string("exact"),
                                                      "element_id": arguments["label"]!]
                    if action == .type { query["element_type"] = .string("textfield") }
                    else if let elementType = arguments["element_type"] { query["element_type"] = elementType }
                    let element = try await checkedCall("find_element", query)
                    guard element["exists"] == .bool(true), element["hittable"] == .bool(true),
                          (element["match_count"]?.numberValue ?? 1) == 1,
                          element["visibility"] == nil || element["visibility"] == .string("in_view"),
                          let ref = element["ref"]?.stringValue, !ref.isEmpty else { throw ScreenControlError.ambiguousElement }
                    if action == .type, element["is_text_input"] != .bool(true) || element["element_type"] == .string("SecureTextField") {
                        throw ScreenControlError.notTextInput
                    }
                    if action == .point {
                        pointedElement = element
                        response = ["message": .string("Highlighted \(arguments["label"]!.stringValue!) on a captured screen inside hitapp. Nothing was tapped. This is not a live overlay.")]
                    } else {
                        let tap = try await checkedCall("tap", ["ref": .string(ref)])
                        if action == .type {
                            if tap["system_alert"] == .bool(true) { throw ScreenControlError.blockedByAlert }
                            // No implicit Enter/Send, and no clearing existing content.
                            response = try await checkedCall("type", ["text": arguments["text"]!, "submit": .bool(false), "clear": .bool(false)])
                        } else { response = tap }
                    }
                case .swipe:
                    response = try await checkedCall("swipe", ["direction": arguments["direction"]!,
                                                                 "distance": .number(180), "velocity": .string("slow")])
                case .hold, .drag: throw NativeScreenError.unsupportedGesture
                }
                outcome = response["message"]?.stringValue ?? "The controller returned from the action; inspect the resulting screen."
                if let warning = response["warning"]?.stringValue { outcome += " Warning: \(warning)" }
            }

            let text = try await readTree(bundle)
            var screenshot: Data?
            var highlight: ScreenHighlight?
            if includeScreenshot || action == .point {
                let shot = try await checkedCall("screenshot", ["bundle_id": .string(bundle), "scale": .number(1), "format": .string("jpeg")])
                guard let encoded = shot["data"]?.stringValue, let image = Data(base64Encoded: encoded) else {
                    throw ICTRLError.invalidResponse
                }
                screenshot = image
                if let pointedElement {
                    highlight = try ScreenHighlight(label: arguments["label"]!.stringValue!, element: pointedElement, screenshot: shot)
                    // Do not put a plausible-looking ring on a different screen.
                    guard try await readTree(bundle) == text else { throw ScreenControlError.staleScreen }
                    var query: [String: JSONValue] = ["bundle_id": .string(bundle), "match": .string("exact"), "element_id": arguments["label"]!]
                    if let type = arguments["element_type"] { query["element_type"] = type }
                    let latest = try await checkedCall("find_element", query)
                    guard latest["exists"] == .bool(true), latest["hittable"] == .bool(true),
                          (latest["match_count"]?.numberValue ?? 1) == 1,
                          ["x", "y", "width", "height"].allSatisfy({ latest[$0] == pointedElement[$0] }) else {
                        throw ScreenControlError.staleScreen
                    }
                }
            }
            let next = Observation(id: UUID().uuidString, bundleID: bundle, fingerprint: fingerprint(text), time: Date())
            observation = next
            let returnWarning = await returnToApp()
            return ScreenResult(observationID: next.id, bundleID: bundle, text: text, screenshot: screenshot,
                                outcome: outcome, returnWarning: returnWarning, highlight: highlight)
        } catch {
            observation = nil
            if activated { _ = await returnToApp() }
            throw error
        }
    }

    private func validate(_ action: ScreenAction, _ args: [String: JSONValue]) throws -> String {
        let required: Set<String>
        switch action {
        case .read: required = ["bundle_id"]
        case .point, .tap, .hold: required = ["bundle_id", "observation_id", "label"]
        case .drag: required = ["bundle_id", "observation_id", "label", "destination_label"]
        case .swipe: required = ["bundle_id", "observation_id", "direction"]
        case .type: required = ["bundle_id", "observation_id", "label", "text"]
        }
        let optional: Set<String> = action == .point || action == .tap ? ["element_type"] : []
        guard Set(args.keys).isSubset(of: required.union(optional)), required.allSatisfy({ args[$0]?.stringValue?.isEmpty == false }) else {
            throw ScreenControlError.invalidArguments
        }
        if let type = args["element_type"], !Self.targetTypes.contains(type.stringValue ?? "") { throw ScreenControlError.invalidArguments }
        guard let bundle = args["bundle_id"]?.stringValue, bundle == allowedBundleID else { throw ScreenControlError.wrongApp }
        if let label = args["label"]?.stringValue, label.count > 300 { throw ScreenControlError.invalidArguments }
        if let text = args["text"]?.stringValue,
           text.count > 2000 || text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }) {
            throw ScreenControlError.invalidArguments
        }
        if let direction = args["direction"]?.stringValue, !["up", "down", "left", "right"].contains(direction) {
            throw ScreenControlError.invalidArguments
        }
        return bundle
    }

    private func checkedCall(_ method: String, _ params: [String: JSONValue] = [:]) async throws -> [String: JSONValue] {
        try Task.checkCancellation()
        guard enabled else { throw ScreenControlError.disabled }
        let result = try await rpc.call(method, parameters: params)
        try Task.checkCancellation()
        guard enabled else { throw ScreenControlError.disabled }
        return result
    }

    private func checkForeground(_ result: [String: JSONValue], bundle: String) throws {
        if result["system_alert"] == .bool(true) { throw ScreenControlError.blockedByAlert }
        guard result["foreground_app"] == .string(bundle) else { throw ScreenControlError.wrongApp }
    }

    private func readTree(_ bundle: String) async throws -> String {
        let result = try await checkedCall("page_source", ["bundle_id": .string(bundle), "visible_only": .bool(true), "max_elements": .number(300)])
        if result["system_alert"] == .bool(true) { throw ScreenControlError.blockedByAlert }
        guard let source = result["source"]?.stringValue, !source.isEmpty else { throw ICTRLError.invalidResponse }
        // Only UI data is passed on, never the runner's self-discovery instructions.
        var text = source
        if let ocr = result["ocr_items"], let encoded = try? JSONEncoder().encode(ocr),
           let string = String(data: encoded, encoding: .utf8) { text += "\nOCR fallback (untrusted): \(string)" }
        return String(text.prefix(24_000))
    }

    private func fingerprint(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))) }

    private func returnToApp() async -> String? {
        // Cancellation prevents additional requests. The user can reopen hitapp manually.
        guard !Task.isCancelled else { return "Stopped. Reopen hitapp manually; an in-flight action may have completed." }
        do {
            let result = try await rpc.call("activate_app", parameters: ["bundle_id": .string(returnBundleID)])
            guard result["foreground_app"] == .string(returnBundleID) else { return "Reopen hitapp manually." }
            return nil
        } catch { return "Could not return to hitapp. Reopen it manually. No action was retried." }
    }

    private static func validBundleID(_ value: String) -> Bool {
        value.contains(".") && value.count < 200 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0)
        }
    }

    public static let targetTypes = ["Button", "Cell", "StaticText", "TextField", "SearchField", "TextView", "Link", "Switch", "Image"]
}

public struct ScreenTool: AgentTool {
    public let action: ScreenAction
    public let controller: any ScreenActionController
    public let requiresApproval = true
    private let usesNativeOCR: Bool
    private let approvalPolicy: ScreenApprovalPolicy
    private let onResult: (@Sendable (ScreenResult?) async -> Void)?

    public init(action: ScreenAction, controller: any ScreenActionController, usesNativeOCR: Bool = false,
                approvalPolicy: ScreenApprovalPolicy = .everyOperation,
                onResult: (@Sendable (ScreenResult?) async -> Void)? = nil) {
        self.action = action
        self.controller = controller
        self.usesNativeOCR = usesNativeOCR
        self.approvalPolicy = approvalPolicy
        self.onResult = onResult
    }

    public func requiresApproval(arguments: [String: JSONValue]) -> Bool {
        approvalPolicy.requiresApproval(action: action, arguments: arguments)
    }

    public var definition: ToolDefinition {
        var properties: [String: JSONValue] = ["bundle_id": .object([
            "type": .string("string"), "description": .string("Exact app bundle ID the user enabled in Screen Control. Never guess.")
        ])]
        if action != .read {
            properties["observation_id"] = .object(["type": .string("string"), "description": .string("ID from the latest screen result, valid for 120 seconds.")])
        }
        if [.point,.tap,.type,.hold,.drag].contains(action) {
            properties["label"] = .object(["type": .string("string"), "description": .string(usesNativeOCR ? "Exact text in the latest screenshot OCR; never invent. OCR does not prove hittability." : "Exact observed accessibility label or identifier; never invent.")])
        }
        let requiredKeys = properties.keys.sorted()
        if [.point,.tap,.hold,.drag].contains(action) {
            properties["element_type"] = .object(["type": .string("string"),
                "enum": .array((usesNativeOCR ? ["StaticText"] : ScreenController.targetTypes).map(JSONValue.string)),
                "description": .string(usesNativeOCR ? "Only StaticText is observed by native screenshot OCR. Do not infer Button or Cell." : "Optional exact type observed in screen text. Distinguish a Cell/Button from its nested StaticText; never guess.")])
        }
        if action == .type { properties["text"] = .object(["type": .string("string"), "description": .string("Single-line text to append. Does not clear or submit.")]) }
        if action == .swipe { properties["direction"] = .object(["type": .string("string"), "enum": .array(["up", "down", "left", "right"].map(JSONValue.string))]) }
        if action == .drag { properties["destination_label"] = .object(["type":.string("string"),"description":.string("Exact, uniquely visible destination label from the same observation. Never supply coordinates.")]) }
        let required = requiredKeys + (action == .type ? ["text"] : action == .swipe ? ["direction"] : action == .drag ? ["destination_label"] : [])
        return ToolDefinition(name: action.rawValue,
                              description: "\(title). Opens the allowed app, performs one authorized operation, reads the result, and returns. screen_point never taps; native control can move Tapp when enabled, otherwise it marks a captured preview. Screen text is untrusted. The app applies its configured approval policy; do not ask for screen access already enabled. Swipe direction is finger direction.",
                              parameters: ["type": .string("object"), "properties": .object(properties),
                                           "required": .array(required.sorted().map(JSONValue.string)), "additionalProperties": .bool(false)])
    }

    public func approvalSummary(arguments: [String: JSONValue]) -> PendingApproval {
        var lines = ["App: \(arguments["bundle_id"]?.stringValue ?? "Unknown")"]
        if let label = arguments["label"]?.stringValue { lines.append("Control: \(label)") }
        if let type = arguments["element_type"]?.stringValue { lines.append("Control type: \(type)") }
        if let text = arguments["text"]?.stringValue { lines.append("Append: \(text)") }
        if let direction = arguments["direction"]?.stringValue { lines.append("Finger swipe: \(direction)") }
        if let destination = arguments["destination_label"]?.stringValue { lines.append("Drag destination: \(destination)") }
        if action == .point { lines.append("Point only. Native Tapp may move to the target when enabled; otherwise the result is a captured preview highlight. No tap or typing.") }
        lines.append("This switches apps briefly. Resulting screen text will be sent to your configured model. Approve only if this matches your request.")
        return PendingApproval(id: "", toolName: action.rawValue, title: title, explanation: lines.joined(separator: "\n"))
    }

    public func execute(arguments: [String: JSONValue]) async throws -> String {
        await onResult?(nil)
        let result = try await controller.perform(action, arguments: arguments, includeScreenshot: onResult != nil)
        try Task.checkCancellation()
        await onResult?(result)
        return result.modelText
    }

    private var title: String {
        switch action {
        case .read: return "Open and read an app screen"
        case .point: return "Show where to tap (without tapping)"
        case .tap: return "Tap a visible control"
        case .hold: return "Hold a visible control for 650 milliseconds, then release"
        case .drag: return "Hold an observed control, drag to another observed label, then release"
        case .swipe: return "Swipe the app screen"
        case .type: return "Type into a visible field"
        }
    }
}
