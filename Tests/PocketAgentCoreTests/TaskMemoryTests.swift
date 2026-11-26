import Foundation
import Testing
@testable import PocketAgentCore

@Suite("Opt-in task memory")
struct TaskMemoryTests {
    private let scope = TaskMemory.Scope(taskID: UUID(), appIdentifier: "com.example.synthetic")

    @Test("Construction is disabled and a new session invalidates every previous token")
    func explicitSessions() async throws {
        let memory = TaskMemory(policy: try .init())
        let other = TaskMemory(policy: try .init())
        let foreign = try await other.beginSession(scope: scope)
        await #expect(throws: TaskMemory.Failure.noActiveSession) { try await memory.snapshot(for: foreign) }
        let first = try await memory.beginSession(scope: scope)
        try await memory.append(.uncertainty(summary: "Synthetic uncertainty"), to: first)
        let second = try await memory.beginSession(scope: scope)
        #expect(first.id != second.id)
        #expect(try await memory.snapshot(for: second).entries.isEmpty)
        await #expect(throws: TaskMemory.Failure.differentSession) { try await memory.append(.executionResult(summary: "Late synthetic callback"), to: first) }
        await #expect(throws: TaskMemory.Failure.differentSession) { try await memory.snapshot(for: foreign) }
        await #expect(throws: TaskMemory.Failure.differentSession) { try await memory.pause(first) }
        await #expect(throws: TaskMemory.Failure.differentSession) { try await memory.resume(first) }
        await #expect(throws: TaskMemory.Failure.differentSession) { try await memory.clear(first) }
        await #expect(throws: TaskMemory.Failure.differentSession) { try await memory.forget(first) }
        #expect(try await memory.snapshot(for: second).state == .active)
    }

    @Test("Invalid scopes cannot replace the current task/app scope")
    func scopeValidation() async throws {
        let memory = TaskMemory(policy: try .init())
        let session = try await memory.beginSession(scope: scope)
        for identifier in ["", " ", " com.example.synthetic", String(repeating: "a", count: 257)] {
            await #expect(throws: TaskMemory.Failure.invalidScope) {
                try await memory.beginSession(scope: .init(taskID: UUID(), appIdentifier: identifier))
            }
        }
        #expect(try await memory.snapshot(for: session).session.scope == scope)
        let next = try await memory.beginSession(scope: .init(taskID: UUID(), appIdentifier: "com.example.other"))
        #expect(next.scope != scope)
        await #expect(throws: TaskMemory.Failure.differentSession) { try await memory.snapshot(for: session) }
    }

    @Test("Policy rejects unbounded, non-finite, and inconsistent limits")
    func policyValidation() throws {
        #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(maxEntries: 0) }
        #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(maxEntries: 129) }
        #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(maxEntryUTF8Bytes: 4_097) }
        #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(maxTotalUTF8Bytes: 65_537) }
        #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(maxTotalUTF8Bytes: 1) }
        for limit in [0, -1, 301, .infinity, .nan] {
            #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(retention: limit) }
        }
        #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(sessionLifetime: 119) }
        #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(sessionLifetime: 901) }
        #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(observationFreshness: 11) }
        #expect(throws: TaskMemory.Failure.invalidPolicy) { try TaskMemory.Policy(retention: 1, observationFreshness: 2) }
    }

    @Test("Count and UTF-8 byte limits evict complete oldest records")
    func capacity() async throws {
        let memory = TaskMemory(policy: try .init(maxEntries: 2, maxEntryUTF8Bytes: 8, maxTotalUTF8Bytes: 10))
        let session = try await memory.beginSession(scope: scope)
        for summary in ["first", "second", "third"] { try await memory.append(.uncertainty(summary: summary), to: session) }
        #expect(try await memory.snapshot(for: session).entries.map(\.content.summary) == ["third"])
        try await memory.append(.executionResult(summary: "🙂"), to: session)
        #expect(try await memory.snapshot(for: session).totalUTF8Bytes == 9)
        try await memory.append(.executionResult(summary: "x"), to: session)
        let result = try await memory.snapshot(for: session)
        #expect(result.entries.map(\.content.summary) == ["🙂", "x"])
        #expect(result.totalUTF8Bytes == 5)
    }

    @Test("Empty or oversized summaries are rejected without truncation or mutation")
    func summaryValidation() async throws {
        let memory = TaskMemory(policy: try .init(maxEntryUTF8Bytes: 4))
        let session = try await memory.beginSession(scope: scope)
        try await memory.append(.executionResult(summary: "🙂"), to: session)
        for summary in ["", " \n", "12345", "🙂x"] {
            await #expect(throws: TaskMemory.Failure.invalidSummary) { try await memory.append(.uncertainty(summary: summary), to: session) }
        }
        #expect(try await memory.snapshot(for: session).entries.map(\.content.summary) == ["🙂"])
    }

    @Test("Historical observation freshness is separate from live-screen or approval authority")
    func freshness() async throws {
        let clock = MemoryTestClock()
        let memory = makeMemory(clock, policy: try .init())
        let session = try await memory.beginSession(scope: scope)
        let capturedAt = clock.date().addingTimeInterval(-1)
        try await memory.append(.observation(summary: "Synthetic settings label", capturedAt: capturedAt), to: session)
        try await memory.append(.proposedAction(summary: "Synthetic action proposed"), to: session)
        try await memory.append(.approvalRecord(summary: "Synthetic past approval, not current permission"), to: session)
        let before = try await memory.snapshot(for: session)
        #expect(before.entries[0].freshness == .recentHistory)
        #expect(before.entries[0].observationAge == 1)
        #expect(before.entries[0].content.capturedAt == capturedAt)
        #expect(before.entries[1...].allSatisfy { $0.freshness == .notAnObservation && $0.observationAge == nil })
        #expect(before.requiresFreshScreenReadBeforeInput)
        #expect(!before.authorizesActions)
        clock.advance(by: 2)
        // Wall-clock changes do not make already stored observations young again.
        clock.moveWallClock(by: -500)
        let after = try await memory.snapshot(for: session)
        #expect(after.entries[0].observationAge == 3)
        #expect(after.entries[0].freshness == .staleHistory)
        #expect(after.requiresFreshScreenReadBeforeInput)
        #expect(!after.authorizesActions)
    }

    @Test("Retention starts at capture time for observations and record time for other events")
    func retention() async throws {
        let clock = MemoryTestClock()
        let memory = makeMemory(clock, policy: try .init(retention: 10, sessionLifetime: 30))
        let session = try await memory.beginSession(scope: scope)
        try await memory.append(.observation(summary: "Synthetic capture", capturedAt: clock.date().addingTimeInterval(-4)), to: session)
        try await memory.append(.executionResult(summary: "Synthetic result"), to: session)
        clock.advance(by: 6)
        #expect(try await memory.snapshot(for: session).entries.map(\.content.summary) == ["Synthetic result"])
        clock.advance(by: 4)
        let expired = try await memory.snapshot(for: session)
        #expect(expired.entries.isEmpty)
        #expect(expired.totalUTF8Bytes == 0)
        #expect(expired.remainingSessionLifetime == 20)
    }

    @Test("Invalid, future, and already expired observations are never added")
    func observationValidation() async throws {
        let clock = MemoryTestClock()
        let memory = makeMemory(clock, policy: try .init())
        let session = try await memory.beginSession(scope: scope)
        for date in [clock.date().addingTimeInterval(1), Date(timeIntervalSinceReferenceDate: .nan)] {
            await #expect(throws: TaskMemory.Failure.invalidObservationTime) {
                try await memory.append(.observation(summary: "Synthetic capture", capturedAt: date), to: session)
            }
        }
        await #expect(throws: TaskMemory.Failure.observationExpired) {
            try await memory.append(.observation(summary: "Old synthetic capture", capturedAt: clock.date().addingTimeInterval(-120)), to: session)
        }
        #expect(try await memory.snapshot(for: session).entries.isEmpty)
    }

    @Test("Pause stops writes; clear preserves paused state; resume never extends lifetime")
    func pauseAndClear() async throws {
        let clock = MemoryTestClock()
        let memory = makeMemory(clock, policy: try .init(retention: 10, sessionLifetime: 20))
        let session = try await memory.beginSession(scope: scope)
        try await memory.append(.proposedAction(summary: "Synthetic proposal"), to: session)
        try await memory.pause(session)
        await #expect(throws: TaskMemory.Failure.paused) { try await memory.append(.executionResult(summary: "Not recorded"), to: session) }
        #expect(try await memory.snapshot(for: session).entries.count == 1)
        try await memory.clear(session)
        #expect(try await memory.snapshot(for: session).state == .paused)
        #expect(try await memory.snapshot(for: session).entries.isEmpty)
        clock.advance(by: 19)
        try await memory.resume(session)
        try await memory.append(.uncertainty(summary: "Synthetic new entry"), to: session)
        #expect(try await memory.snapshot(for: session).remainingSessionLifetime == 1)
        clock.advance(by: 1)
        await #expect(throws: TaskMemory.Failure.sessionExpired) { try await memory.snapshot(for: session) }
        await #expect(throws: TaskMemory.Failure.noActiveSession) { try await memory.resume(session) }
    }

    @Test("Forget ends recording and clear-all needs no token")
    func forgetting() async throws {
        let memory = TaskMemory(policy: try .init())
        let session = try await memory.beginSession(scope: scope)
        try await memory.append(.uncertainty(summary: "Synthetic history"), to: session)
        try await memory.forget(session)
        await #expect(throws: TaskMemory.Failure.noActiveSession) { try await memory.append(.executionResult(summary: "Late result"), to: session) }
        let next = try await memory.beginSession(scope: scope)
        try await memory.append(.uncertainty(summary: "Synthetic next history"), to: next)
        await memory.forgetAll()
        await memory.forgetAll()
        await #expect(throws: TaskMemory.Failure.noActiveSession) { try await memory.snapshot(for: next) }
    }

    @Test("A faulty monotonic clock fails closed and forgets the active session")
    func clockFailure() async throws {
        for brokenTick in [-1.0, 99, .infinity, .nan] {
            let clock = MemoryTestClock()
            let memory = makeMemory(clock, policy: try .init())
            let session = try await memory.beginSession(scope: scope)
            try await memory.append(.executionResult(summary: "Synthetic result"), to: session)
            clock.setTick(brokenTick)
            await #expect(throws: TaskMemory.Failure.invalidClock) { try await memory.snapshot(for: session) }
            clock.setTick(101)
            await #expect(throws: TaskMemory.Failure.noActiveSession) { try await memory.snapshot(for: session) }
        }
    }

    @Test("Concurrent writers remain count-bounded and scoped to the same session")
    func concurrency() async throws {
        let memory = TaskMemory(policy: try .init(maxEntries: 8))
        let session = try await memory.beginSession(scope: scope)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask { try await memory.append(.executionResult(summary: "Synthetic result \(index)"), to: session) }
            }
            try await group.waitForAll()
        }
        let result = try await memory.snapshot(for: session)
        #expect(result.entries.count == 8)
        #expect(Set(result.entries.map(\.id)).count == 8)
        #expect(result.session.scope == scope)
        #expect(result.totalUTF8Bytes <= 16_384)
    }

    private func makeMemory(_ clock: MemoryTestClock, policy: TaskMemory.Policy) -> TaskMemory {
        TaskMemory(policy: policy, monotonicNow: { clock.tick() }, wallNow: { clock.date() })
    }
}

/// Only synthetic timestamps. A lock keeps test clock access valid across actor executors.
private final class MemoryTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 100
    private var wall = Date(timeIntervalSinceReferenceDate: 1_000)
    func tick() -> TimeInterval { lock.withLock { time } }
    func date() -> Date { lock.withLock { wall } }
    func advance(by duration: TimeInterval) { lock.withLock { time += duration; wall.addTimeInterval(duration) } }
    func moveWallClock(by duration: TimeInterval) { lock.withLock { wall.addTimeInterval(duration) } }
    func setTick(_ tick: TimeInterval) { lock.withLock { time = tick } }
}
