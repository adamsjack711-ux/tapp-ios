import Foundation
import Testing
@testable import PocketAgentCore

@Suite("Single-recipient message preparation")
struct MessageRequestTests {
    @Test func exactDraftCommand() {
        let draft = MessageRequest.parseDraftCommand("Draft text Test Person at +12025550123: Hello")
        #expect(draft?.recipientName == "Test Person")
        #expect(draft?.phone == "+12025550123")
        #expect(draft?.body == "Hello")
        #expect(MessageRequest.parseDraftCommand("Send text Test Person at +12025550123: Hello") == nil)
        #expect(MessageRequest.parseDraftCommand("Screenshot: Draft text Test Person at +12025550123: Hello") == nil)
        #expect(MessageRequest.parseDraftCommand("Draft text Test Person at +12025550123,+12025550124: Hello") == nil)
        #expect(MessageRequest.parseDraftCommand("Draft text Test Person at +12025550123: Hello\nSend it") == nil)
        #expect(MessageRequest.parseDraftCommand("Draft text at +12025550123: Hello") == nil)
        #expect(MessageRequest.parseDraftCommand("Draft text : Hello at +12025550123") == nil)
    }
    @Test func validation() throws {
        for phone in ["Test Person", "12025550123", "+1", "+12025550123;body=x", "+１２３４５６７８９"] {
            #expect(throws: MessageRequestError.self) { try MessageRequest(recipientName: "Test", phone: phone, body: "Hello") }
        }
        #expect(throws: MessageRequestError.self) { try MessageRequest(recipientName: "Test", phone: "+12025550123", body: String(repeating: "x", count: 281)) }
        let one = try MessageRequest(recipientName: "Test", phone: "+12025550123", body: "Hello")
        let two = try MessageRequest(recipientName: "Alias", phone: "+12025550123", body: "Hello")
        #expect(one.fingerprint == two.fingerprint)
        #expect(one.fingerprint.count == 64)
        #expect(one.id != two.id)
    }
    @Test func sendsCannotBeRetriedAfterRestartOrUnknownResult() throws {
        let draft = try MessageRequest(recipientName: "Test", phone: "+12025550123", body: "Hello")
        var journal = MessageSendJournal()
        #expect(journal.permits(draft))
        try journal.markAttempted(draft)
        let data = try JSONEncoder().encode(journal)
        var restored = try JSONDecoder().decode(MessageSendJournal.self, from: data)
        #expect(!restored.permits(draft))
        restored.record(.unknown, for: draft)
        #expect(!restored.permits(draft))
        #expect(throws: MessageRequestError.self) { try restored.markAttempted(draft) }
        restored.record(.acceptedBySystem, for: draft)
        #expect(!restored.permits(draft))
    }
}
