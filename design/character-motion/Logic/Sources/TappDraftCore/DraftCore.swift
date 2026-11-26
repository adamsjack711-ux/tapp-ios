import Foundation

// This gate controls only a disposable counter in the draft. No device input.
struct ActionGate {
    enum Phase: String { case ready, pointing, acting, verified, stopped, failed }
    enum Blocker: Error, Equatable { case busy, wrongScope, permission, stale, expired, cancelled, replay, guideOnly }
    struct Observation: Equatable {
        let id: UUID
        let revision: Int
        let count: Int
        let capturedAt: TimeInterval
        let scope: String
    }
    private(set) var phase: Phase = .ready
    private(set) var active: Observation?
    private(set) var consumed: Set<UUID> = []
    private(set) var generation = 0
    private(set) var inputCount = 0
    var busy: Bool { phase == .pointing || phase == .acting }
    mutating func begin(count: Int, revision: Int, now: TimeInterval, scope: String, allowed: Bool) throws -> Observation {
        guard !busy else { throw Blocker.busy }
        guard scope == "local-counter" else { throw Blocker.wrongScope }
        guard allowed else { throw Blocker.permission }
        let observation = Observation(id: UUID(), revision: revision, count: count, capturedAt: now, scope: scope)
        active = observation; phase = .pointing
        return observation
    }
    mutating func authorize(_ observation: Observation, revision: Int, count: Int, now: TimeInterval, scope: String, allowed: Bool, guideOnly: Bool) throws {
        guard !consumed.contains(observation.id) else { throw Blocker.replay }
        guard active == observation, phase == .pointing else { throw Blocker.cancelled }
        guard scope == observation.scope else { fail(); throw Blocker.wrongScope }
        guard allowed else { fail(); throw Blocker.permission }
        guard !guideOnly else { fail(); throw Blocker.guideOnly }
        guard revision == observation.revision, count == observation.count else { fail(); throw Blocker.stale }
        guard now >= observation.capturedAt, now - observation.capturedAt <= 5 else { fail(); throw Blocker.expired }
        // Consume before the callback. An unknown outcome must never replay input.
        consumed.insert(observation.id); phase = .acting; inputCount += 1
    }
    @discardableResult mutating func verify(_ observation: Observation, observedCount: Int) -> Bool {
        guard active == observation, phase == .acting else { return false }
        let passed = observedCount == observation.count + 1
        phase = passed ? .verified : .failed; active = nil
        return passed
    }
    mutating func finishGuide() { guard phase == .pointing else { return }; active = nil; phase = .ready }
    mutating func stop() { generation += 1; active = nil; phase = .stopped }
    mutating func fail() { active = nil; phase = .failed }
}

enum CursorRules {
    static func position(x: Double, y: Double, width: Double, height: Double, size: Double) -> (x: Double, y: Double) {
        guard width.isFinite, height.isFinite, size.isFinite, width > 0, height > 0 else { return (0, 0) }
        let margin = max(0, min(size / 2 + 8, min(width, height) / 2))
        let safeX = x.isFinite ? x : width / 2
        let safeY = y.isFinite ? y : height / 2
        return (min(max(safeX, margin), width - margin), min(max(safeY, margin), height - margin))
    }
    static func visible(active: Bool, typing: Bool, capturing: Bool) -> Bool { active && !typing && !capturing }
    static func canTravel(quiet: Bool, reduceMotion: Bool, busy: Bool, idleMode: String) -> Bool {
        !quiet && !reduceMotion && !busy && idleMode != "Stay still"
    }
    static func restingOpacity(_ idleMode: String) -> Double { idleMode == "Fade away" ? 0 : idleMode == "Stay still" ? 0.65 : 0.35 }
}
