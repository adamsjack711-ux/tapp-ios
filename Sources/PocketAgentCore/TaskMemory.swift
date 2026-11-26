import Foundation

/// Opt-in, process-local history for one bounded task and app scope.
///
/// This type does not capture, redact, persist, transmit, or execute anything. Callers must
/// exclude secrets and unnecessary personal data before recording a summary. Historical
/// approval records are never authorization, and even a recent observation requires a new
/// screen read before input. There is deliberately no Codable or tool/approval conformance.
/// Expiry is enforced on access; a lifecycle owner must call clear/forget when a task ends.
/// Previously returned value copies cannot be recalled or securely erased by this buffer.
public actor TaskMemory {
    public enum Failure: Error, Equatable, Sendable {
        case invalidPolicy, invalidScope, noActiveSession, differentSession, sessionExpired
        case paused, invalidSummary, invalidObservationTime, observationExpired, invalidClock
    }

    public struct Policy: Equatable, Sendable {
        public let maxEntries: Int
        public let maxEntryUTF8Bytes: Int
        public let maxTotalUTF8Bytes: Int
        public let retention: TimeInterval
        public let sessionLifetime: TimeInterval
        public let observationFreshness: TimeInterval

        /// Hard ceilings prevent a caller from accidentally creating durable/unbounded history.
        public init(
            maxEntries: Int = 32,
            maxEntryUTF8Bytes: Int = 2_048,
            maxTotalUTF8Bytes: Int = 16_384,
            retention: TimeInterval = 120,
            sessionLifetime: TimeInterval = 300,
            observationFreshness: TimeInterval = 3
        ) throws {
            guard (1...128).contains(maxEntries),
                  (1...4_096).contains(maxEntryUTF8Bytes),
                  (maxEntryUTF8Bytes...65_536).contains(maxTotalUTF8Bytes),
                  retention.isFinite, retention > 0, retention <= 300,
                  sessionLifetime.isFinite, sessionLifetime >= retention, sessionLifetime <= 900,
                  observationFreshness.isFinite, observationFreshness > 0,
                  observationFreshness <= min(10, retention) else { throw Failure.invalidPolicy }
            self.maxEntries = maxEntries
            self.maxEntryUTF8Bytes = maxEntryUTF8Bytes
            self.maxTotalUTF8Bytes = maxTotalUTF8Bytes
            self.retention = retention
            self.sessionLifetime = sessionLifetime
            self.observationFreshness = observationFreshness
        }
    }

    /// Scope is caller-supplied provenance, not evidence of permission or the foreground app.
    public struct Scope: Equatable, Sendable {
        public let taskID: UUID
        public let appIdentifier: String

        public init(taskID: UUID, appIdentifier: String) {
            self.taskID = taskID
            self.appIdentifier = appIdentifier
        }
    }

    public struct Session: Equatable, Sendable {
        public let id: UUID
        public let scope: Scope
        fileprivate init(scope: Scope) { self.id = UUID(); self.scope = scope }
    }

    public enum Content: Equatable, Sendable {
        case observation(summary: String, capturedAt: Date)
        case proposedAction(summary: String)
        case approvalRecord(summary: String)
        case executionResult(summary: String)
        case uncertainty(summary: String)

        public var summary: String {
            switch self {
            case .observation(let summary, _), .proposedAction(let summary),
                 .approvalRecord(let summary), .executionResult(let summary),
                 .uncertainty(let summary): return summary
            }
        }

        public var capturedAt: Date? {
            if case .observation(_, let date) = self { return date }
            return nil
        }
    }

    public enum State: Equatable, Sendable { case active, paused }
    public enum Freshness: Equatable, Sendable {
        /// A recent historical observation, never proof of the screen's current state.
        case recentHistory
        case staleHistory
        case notAnObservation
    }

    public struct Entry: Equatable, Sendable {
        public let id: UUID
        public let content: Content
        public let recordedAt: Date
        public let observationAge: TimeInterval?
        public let freshness: Freshness
    }

    public struct Snapshot: Equatable, Sendable {
        public let session: Session
        public let state: State
        public let entries: [Entry]
        public let totalUTF8Bytes: Int
        public let remainingSessionLifetime: TimeInterval
        /// These invariants also apply to recent observations and approvalRecord entries.
        public var requiresFreshScreenReadBeforeInput: Bool { true }
        public var authorizesActions: Bool { false }
    }

    private struct StoredEntry {
        let id: UUID
        let content: Content
        let recordedAt: Date
        let recordedTick: TimeInterval
        let initialObservationAge: TimeInterval?
        let byteCount: Int
        let expiresAt: TimeInterval
    }

    private struct ActiveSession {
        let token: Session
        let startedAt: TimeInterval
        var state = State.active
        var entries: [StoredEntry] = []
    }

    private let policy: Policy
    private let monotonicNow: @Sendable () -> TimeInterval
    private let wallNow: @Sendable () -> Date
    private var current: ActiveSession?
    private var lastTick: TimeInterval?

    /// Construction starts disabled. beginSession is the explicit recording opt-in.
    public init(
        policy: Policy,
        monotonicNow: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        wallNow: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.policy = policy
        self.monotonicNow = monotonicNow
        self.wallNow = wallNow
    }

    /// Starting a new session forgets the old one, even when its task/app scope is identical.
    /// It does not grant screen permission, start capture, or extend an existing session.
    public func beginSession(scope: Scope) throws -> Session {
        guard !scope.appIdentifier.isEmpty, scope.appIdentifier.utf8.count <= 256,
              scope.appIdentifier == scope.appIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        else { throw Failure.invalidScope }
        let now = try tick()
        let token = Session(scope: scope)
        current = ActiveSession(token: token, startedAt: now)
        return token
    }

    public func append(_ content: Content, to session: Session) throws {
        let now = try tick()
        var active = try validated(session, at: now)
        guard active.state == .active else { throw Failure.paused }
        let bytes = content.summary.utf8.count
        guard bytes > 0, bytes <= policy.maxEntryUTF8Bytes,
              !content.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw Failure.invalidSummary }
        let date = wallNow()
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw Failure.invalidClock }
        let age = content.capturedAt.map { date.timeIntervalSince($0) }
        if let age {
            guard age.isFinite, age >= 0 else { throw Failure.invalidObservationTime }
            guard age < policy.retention else { throw Failure.observationExpired }
        }
        active.entries.append(StoredEntry(
            id: UUID(), content: content, recordedAt: date, recordedTick: now,
            initialObservationAge: age, byteCount: bytes,
            expiresAt: now + policy.retention - (age ?? 0)
        ))
        // Drop whole oldest entries rather than truncate a summary's meaning or provenance.
        while active.entries.count > policy.maxEntries || active.entries.reduce(0, { $0 + $1.byteCount }) > policy.maxTotalUTF8Bytes {
            active.entries.removeFirst()
        }
        current = active
    }

    public func snapshot(for session: Session) throws -> Snapshot {
        let now = try tick()
        let active = try validated(session, at: now)
        let entries = active.entries.map { stored in
            let age = stored.initialObservationAge.map { $0 + now - stored.recordedTick }
            return Entry(
                id: stored.id, content: stored.content, recordedAt: stored.recordedAt,
                observationAge: age,
                freshness: age.map { $0 < policy.observationFreshness ? .recentHistory : .staleHistory } ?? .notAnObservation
            )
        }
        return Snapshot(
            session: active.token, state: active.state, entries: entries,
            totalUTF8Bytes: active.entries.reduce(0, { $0 + $1.byteCount }),
            remainingSessionLifetime: policy.sessionLifetime - (now - active.startedAt)
        )
    }

    /// Pause rejects new entries. Existing history remains readable until its original expiry.
    public func pause(_ session: Session) throws { try setState(.paused, for: session) }
    public func resume(_ session: Session) throws { try setState(.active, for: session) }

    /// Clears buffered entries without resuming recording or extending the session deadline.
    public func clear(_ session: Session) throws {
        var active = try validated(session, at: tick())
        active.entries.removeAll()
        current = active
    }

    /// Ends this session. A late callback carrying its old token cannot record into a new one.
    public func forget(_ session: Session) throws {
        _ = try validated(session, at: tick())
        current = nil
    }

    /// Unconditional local privacy reset, also usable after an expiry or clock error.
    public func forgetAll() { current = nil }

    private func setState(_ state: State, for session: Session) throws {
        var active = try validated(session, at: tick())
        active.state = state
        current = active
    }

    private func validated(_ session: Session, at now: TimeInterval) throws -> ActiveSession {
        guard var active = current else { throw Failure.noActiveSession }
        if now - active.startedAt >= policy.sessionLifetime {
            current = nil
            throw Failure.sessionExpired
        }
        active.entries.removeAll { now >= $0.expiresAt }
        current = active
        guard active.token == session else { throw Failure.differentSession }
        return active
    }

    private func tick() throws -> TimeInterval {
        let now = monotonicNow()
        guard now.isFinite, now >= 0, lastTick.map({ now >= $0 }) ?? true else {
            current = nil
            lastTick = nil
            throw Failure.invalidClock
        }
        lastTick = now
        return now
    }
}
