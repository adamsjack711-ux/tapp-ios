import XCTest
import CoreGraphics
@testable import TappMotion

final class TappMotionTests: XCTestCase {
    func testClampKeepsEntireCursorInsideCanvas() {
        var motion = TappMotion()
        motion.resize(.init(width: 300, height: 400))
        motion.move(to: .init(x: -999, y: 999))
        XCTAssertEqual(motion.target, .init(x: 16, y: 384))
        for _ in 0..<500 { motion.step(seconds: 1.0 / 60) }
        XCTAssertEqual(motion.position, motion.target)
        XCTAssertFalse(motion.moving)
    }

    func testStopCannotResumeOldTarget() {
        var motion = TappMotion()
        motion.resize(.init(width: 300, height: 400))
        motion.move(to: .init(x: 260, y: 350))
        motion.step(seconds: 0.016)
        motion.stop()
        let stopped = motion.position
        for _ in 0..<100 { motion.step(seconds: 1) }
        XCTAssertEqual(motion.position, stopped)
        XCTAssertFalse(motion.moving)
    }

    func testParkArrivesExactlyAtCentreWithoutOvershoot() {
        var motion = TappMotion()
        motion.resize(.init(width: 300, height: 400))
        motion.move(to: .init(x: 280, y: 380))
        for _ in 0..<500 { motion.step(seconds: 0.016) }
        motion.park()
        for _ in 0..<500 { motion.step(seconds: 0.016) }
        XCTAssertEqual(motion.position, .init(x: 150, y: 200))
        XCTAssertFalse(motion.moving)
    }

    func testGeometryChangeCancelsOldRoute() {
        var motion = TappMotion()
        motion.resize(.init(width: 300, height: 400))
        motion.move(to: .init(x: 260, y: 350))
        motion.resize(.init(width: 400, height: 300))
        XCTAssertEqual(motion.position, .init(x: 200, y: 150))
        XCTAssertFalse(motion.moving)
        motion.resize(.zero)
        motion.move(to: .init(x: 100, y: 100))
        XCTAssertFalse(motion.moving)
    }

    func testInvalidInputAndLongFrameGap() {
        var motion = TappMotion()
        motion.resize(.init(width: 300, height: 400))
        motion.move(to: .init(x: CGFloat.infinity, y: 20))
        XCTAssertFalse(motion.moving)
        motion.move(to: .init(x: 280, y: 380))
        let before = motion.position
        motion.step(seconds: .nan)
        motion.step(seconds: -2)
        XCTAssertEqual(before, motion.position)
        motion.step(seconds: 999)
        XCTAssertLessThanOrEqual(hypot(motion.position.x - before.x, motion.position.y - before.y), 21.001)
    }
}
