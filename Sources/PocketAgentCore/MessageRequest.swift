import Foundation
import CryptoKit

/// User-entered command only. Never parse OCR or model output through this path.
public struct MessageRequest: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let recipientName: String
    public let phone: String
    public let body: String

    public init(recipientName: String, phone: String, body: String) throws {
        guard !recipientName.isEmpty, recipientName.count <= 80,
              !recipientName.contains(where: { $0.isNewline }),
              phone.first == "+", (9...16).contains(phone.count),
              phone.dropFirst().first != "0",
              phone.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }),
              !body.isEmpty, body.count <= 280, !body.contains(where: { $0.isNewline }) else {
            throw MessageRequestError.invalid
        }
        self.recipientName = recipientName; self.phone = phone; self.body = body
    }

    /// Format: Draft text Lalith at +12345678901: Hello
    public static func parseDraftCommand(_ text: String) -> Self? {
        let prefix = "draft text "
        guard text.lowercased().hasPrefix(prefix),
              let separator = text.range(of: ": "),
              let numberSeparator = text.range(of: " at +", options: .backwards, range: text.startIndex..<separator.lowerBound),
              let nameStart = text.index(text.startIndex, offsetBy: prefix.count, limitedBy: numberSeparator.lowerBound),
              nameStart < numberSeparator.lowerBound else { return nil }
        let name = String(text[nameStart..<numberSeparator.lowerBound])
        let phone = String(text[text.index(numberSeparator.lowerBound, offsetBy: 4)..<separator.lowerBound])
        let body = String(text[separator.upperBound...])
        return try? Self(recipientName: name, phone: phone, body: body)
    }

    /// Store no cleartext phone/body in the single-send journal.
    public var fingerprint: String {
        SHA256.hash(data: Data((phone + "\u{0}" + body).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// An attempted send is never automatically replayable, including after a
/// crash or an ambiguous result. The owner explicitly resolves unknown sends.
public struct MessageSendJournal: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable { case attempted, acceptedBySystem, failed, unknown }
    public private(set) var entries: [String: Outcome] = [:]
    public init() {}
    public func permits(_ request: MessageRequest) -> Bool { entries[request.fingerprint] == nil && entries.count < 100 }
    public mutating func markAttempted(_ request: MessageRequest) throws {
        guard permits(request) else { throw MessageRequestError.repeated }
        entries[request.fingerprint] = .attempted
    }
    public mutating func record(_ outcome: Outcome, for request: MessageRequest) {
        guard entries[request.fingerprint] != nil else { return }
        entries[request.fingerprint] = outcome
    }
}

public enum MessageRequestError: LocalizedError {
    case invalid, unavailable, busy, interrupted, repeated, ambiguous
    public var errorDescription: String? {
        switch self {
        case .invalid: "Use one recipient name, an international phone number and a single-line message of 1–280 characters."
        case .unavailable: "iOS messaging is not available on this device. Nothing was sent."
        case .busy: "Finish or cancel the current message first."
        case .interrupted: "Message composition ended without a confirmed result. Inspect Messages; do not retry Send."
        case .repeated: "A send was already attempted for this recipient and text. Inspect Messages before preparing another send."
        case .ambiguous: "The message recipient, text or Send control could not be verified. No Send tap was issued."
        }
    }
}
