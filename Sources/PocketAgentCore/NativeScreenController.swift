import Foundation

public struct NativeScreenText: Codable, Equatable, Sendable {
    public let label: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(label: String, x: Double, y: Double, width: Double, height: Double) {
        self.label = label; self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var valid: Bool {
        !label.isEmpty && [x, y, width, height].allSatisfy(\.isFinite) &&
        x >= 0 && y >= 0.10 && width > 0 && height > 0 && x + width <= 1 && y + height <= 0.96
    }
    /// Keep the arrow below the glyphs, centred horizontally so a wider label
    /// cannot push the arrow beyond the right edge of the display.
    public var cursorAnchor:(x:Double,y:Double) {
        (x+width/2,y+height*0.995)
    }
    public func hasSameBounds(as other:NativeScreenText) -> Bool {
        // OCR can move each edge by a few pixels independently. Compare edges,
        // not width/height differences that add the two rounding errors.
        abs(x-other.x)<0.006 && abs(y-other.y)<0.006 &&
        abs((x+width)-(other.x+other.width))<0.006 &&
        abs((y+height)-(other.y+other.height))<0.006
    }
}

public struct NativeScreenFrame: Sendable {
    public let image: Data
    public let items: [NativeScreenText]
    public init(image: Data, items: [NativeScreenText]) {
        self.image = image; self.items = items.filter(\.valid)
    }
    public var text: String {
        "Screenshot OCR, not an accessibility tree. Observed type: StaticText. Exact visible labels:\n" +
        items.map { $0.label }.joined(separator: "\n")
    }
    /// Excludes status bar/Island and allows tiny OCR geometry jitter only.
    public func sameContent(as other: NativeScreenFrame) -> Bool {
        guard items.count == other.items.count else { return false }
        var remaining = other.items
        return items.allSatisfy { a in
            guard let index = remaining.firstIndex(where: { b in
            a.label == b.label && a.hasSameBounds(as:b)
            }) else { return false }
            remaining.remove(at: index)
            return true
        }
    }
    public var containsPermissionPrompt: Bool {
        let value = items.map(\.label).joined(separator: " ").lowercased()
        return ["would like to", "trust this computer", "enter passcode", "enter your password",
                "allow access", "permission required", "sign in to your apple", "vpn configurations"].contains { value.contains($0) }
    }

    public func revalidatedTapTarget(_ target:NativeScreenText, matching previous:NativeScreenFrame) throws -> NativeScreenText {
        guard !containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
        guard sameContent(as:previous) else { throw ScreenControlError.staleScreen }
        let matches=items.filter { $0.label == target.label }
        guard matches.count==1,let match=matches.first,match.hasSameBounds(as:target) else {
            throw ScreenControlError.staleScreen
        }
        return match
    }
}

/// On-phone native device implementation supplies pixels and OCR. It must not
/// invoke XCTest, silently fall back to another engine or execute model code.
public protocol NativeScreenDevice: Sendable {
    func begin(bundleID: String, operationID: UUID) async throws
    func openAllowedApp() async throws
    func captureFrame() async throws -> NativeScreenFrame
    func tap(_ target: NativeScreenText) async throws
    func swipe(direction: String) async throws
    func finish() async -> String?
    func cancel(operationID: UUID) async
}

/// Opt-in for devices that re-capture and validate this exact observation
/// immediately before dispatching a tap. Moving toward an old observation is
/// harmless; sending input against it without that fresh check is forbidden.
public protocol NativeScreenRevalidatingTapDevice: NativeScreenDevice {
    func prepareTapObservation(_ frame:NativeScreenFrame) async throws
}

/// Optional native primitives. Both endpoints are resolved from the same
/// fresh observation; the model never controls coordinates or hold duration.
public protocol NativeScreenGestureDevice: NativeScreenDevice {
    func hold(_ target:NativeScreenText) async throws
    func drag(_ target:NativeScreenText,to destination:NativeScreenText) async throws
}

/// Optional live cursor transport. Input remains owned by NativeScreenDevice;
/// a cursor failure must never fall through to an unseen tap.
public protocol NativeScreenCursor: Sendable {
    func isEnabled() async -> Bool
    func move(to target: NativeScreenText) async throws
    func cancelMotion() async
}

public enum NativeScreenError: LocalizedError {
    case unsupportedTyping, unsupportedGesture, unreadable, protectedControl, notPaired
    public var errorDescription: String? {
        switch self {
        case .unsupportedTyping: "Native typing is not supported yet. Type this yourself; XCTest will not be started."
        case .unsupportedGesture: "This controller does not support native hold and drag gestures. No input was sent."
        case .unreadable: "No readable screen content. No action was sent."
        case .protectedControl: "This control may authorize access or enter credentials. Handle it yourself."
        case .notPaired: "The approved native developer identity is missing. Provision native pairing; do not start the legacy XCTest helper."
        }
    }
}

/// Shares the agent's one-operation approval boundary; never replays approval.
/// OCR is an observation aid, not an accessibility/hittability or security claim.
public actor NativeScreenController: ScreenActionController {
    private struct Observation { let id: String; let frame: NativeScreenFrame; let time: Date }
    private let device: any NativeScreenDevice
    private let cursor: (any NativeScreenCursor)?
    private var enabled = false
    private var mode: ScreenInteractionMode = .guide
    private var bundle = ""
    private var busy = false
    private var observation: Observation?
    private var operationID: UUID?

    public init(device: any NativeScreenDevice, cursor: (any NativeScreenCursor)? = nil) {
        self.device = device; self.cursor = cursor
    }

    public func configure(enabled: Bool, allowedBundleID: String, mode: ScreenInteractionMode = .guide) throws {
        guard !busy else { throw ScreenControlError.busy }
        guard allowedBundleID.contains("."), allowedBundleID.count < 200,
              !["com.apple.springboard", "com.jackadamslovell.PocketAgent"].contains(allowedBundleID),
              allowedBundleID.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0) }) else {
            throw ScreenControlError.invalidArguments
        }
        self.enabled = enabled; bundle = allowedBundleID; self.mode = mode; observation = nil
    }

    public func disable() async {
        enabled = false; observation = nil
        await cursor?.cancelMotion()
        if let operationID { await device.cancel(operationID: operationID) }
    }

    public func perform(_ action: ScreenAction, arguments: [String: JSONValue], includeScreenshot: Bool = true) async throws -> ScreenResult {
        guard enabled else { throw ScreenControlError.disabled }
        guard !busy else { throw ScreenControlError.busy }
        guard arguments["bundle_id"] == .string(bundle) else { throw ScreenControlError.wrongApp }
        guard mode == .act || action == .read || action == .point else { throw ScreenControlError.guideOnly }
        guard action != .type else { throw NativeScreenError.unsupportedTyping }
        if [.hold,.drag].contains(action), !(device is any NativeScreenGestureDevice) { throw NativeScreenError.unsupportedGesture }
        let required: Set<String> = action == .read ? ["bundle_id"] :
            action == .swipe ? ["bundle_id", "observation_id", "direction"] :
            action == .drag ? ["bundle_id", "observation_id", "label", "destination_label"] : ["bundle_id", "observation_id", "label"]
        let optional: Set<String> = [.point,.tap,.hold,.drag].contains(action) ? ["element_type"] : []
        guard Set(arguments.keys).isSubset(of: required.union(optional)),
              required.allSatisfy({ arguments[$0]?.stringValue?.isEmpty == false }),
              arguments["element_type"] == nil || arguments["element_type"] == .string("StaticText") else { throw ScreenControlError.invalidArguments }
        if action == .swipe, !["up", "down", "left", "right"].contains(arguments["direction"]?.stringValue ?? "") { throw ScreenControlError.invalidArguments }
        let previous = observation
        if action != .read {
            guard let previous, arguments["observation_id"] == .string(previous.id),
                  Date().timeIntervalSince(previous.time) < 120 else { throw ScreenControlError.staleScreen }
        }
        busy = true
        let id = UUID()
        operationID = id
        observation = nil // Consume before any await; an error cannot replay it.
        defer { busy = false; operationID = nil }
        return try await withTaskCancellationHandler {
            do {
                try check()
                try await device.begin(bundleID: bundle, operationID: id)
                try check()
                try await device.openAllowedApp()
                try check()
                var frame:NativeScreenFrame
                if action == .tap, let previous,
                   let revalidating = device as? any NativeScreenRevalidatingTapDevice {
                    try await revalidating.prepareTapObservation(previous.frame)
                    frame = previous.frame
                } else {
                    frame = try await device.captureFrame()
                }
                try check()
                guard !frame.items.isEmpty else { throw NativeScreenError.unreadable }
                if frame.containsPermissionPrompt { throw ScreenControlError.blockedByAlert }
                var highlight: ScreenHighlight?
                var outcome = "Opened the requested app and captured visible text using native screenshot OCR."
                if action != .read {
                    guard let previous, previous.frame.sameContent(as: frame) else { throw ScreenControlError.staleScreen }
                    if action == .swipe {
                        try await device.swipe(direction: arguments["direction"]!.stringValue!)
                        outcome = "Sent one native swipe. Inspect the resulting capture."
                    } else {
                        let label = arguments["label"]!.stringValue!
                        guard label.count <= 300 else { throw ScreenControlError.invalidArguments }
                        let matches = frame.items.filter { $0.label == label }
                        guard matches.count == 1, let target = matches.first else { throw ScreenControlError.ambiguousElement }
                        highlight = try ScreenHighlight(label: label, element: [
                            "x": .number(target.x), "y": .number(target.y), "width": .number(target.width), "height": .number(target.height)
                        ], screenshot: ["point_width": .number(1), "point_height": .number(1)])
                        let liveCursor = await cursor?.isEnabled() == true
                        if liveCursor {
                            try check()
                            try await cursor?.move(to: target)
                            try check()
                        }
                        if [.tap,.hold,.drag].contains(action) {
                            guard !["allow", "trust", "allow while using app", "allow once", "password", "passcode", "face id", "touch id"].contains(label.lowercased()) else { throw NativeScreenError.protectedControl }
                            try check()
                            if action == .tap {
                                try await device.tap(target)
                            } else if let gestures=device as? any NativeScreenGestureDevice {
                                if action == .hold { try await gestures.hold(target) }
                                else {
                                    let destinationLabel=arguments["destination_label"]!.stringValue!
                                    guard destinationLabel.count<=300,destinationLabel != label else { throw ScreenControlError.invalidArguments }
                                    let destinations=frame.items.filter { $0.label==destinationLabel }
                                    guard destinations.count==1,let destination=destinations.first,destination.valid else { throw ScreenControlError.ambiguousElement }
                                    guard !["allow","trust","password","passcode","face id","touch id"].contains(destinationLabel.lowercased()) else { throw NativeScreenError.protectedControl }
                                    try await gestures.drag(target,to:destination)
                                }
                            } else { throw NativeScreenError.unsupportedGesture }
                            highlight = nil
                            outcome = "Sent one native \(action == .tap ? "tap" : action == .hold ? "hold and release" : "held drag and release") at uniquely observed text. OCR does not prove the intended effect; inspect the resulting capture."
                        } else {
                            outcome = liveCursor ? "Moved Tapp to the observed text. Nothing was tapped." :
                                "Highlighted the observed text on a captured screen. Nothing was tapped."
                        }
                    }
                    try check()
                    if action != .point { frame = try await device.captureFrame() }
                }
                try check()
                // Preserve the result of a sent action, but never grant a new
                // observation for acting on a permission/credential prompt.
                let blocked = frame.containsPermissionPrompt
                if blocked { outcome += " A permission or credential prompt appeared. Handle it yourself; no further action is authorized." }
                let next = Observation(id: UUID().uuidString, frame: frame, time: .now)
                let warning = await device.finish()
                try check()
                observation = blocked || frame.items.isEmpty ? nil : next
                return ScreenResult(observationID: next.id, bundleID: bundle, text: frame.text,
                    screenshot: includeScreenshot ? frame.image : nil, outcome: outcome, returnWarning: warning, highlight: highlight)
            } catch {
                await cursor?.cancelMotion()
                _ = await device.finish()
                throw error
            }
        } onCancel: { [device, cursor] in Task {
            await cursor?.cancelMotion()
            await device.cancel(operationID: id)
        } }
    }

    private func check() throws {
        try Task.checkCancellation()
        guard enabled else { throw ScreenControlError.disabled }
    }
}
