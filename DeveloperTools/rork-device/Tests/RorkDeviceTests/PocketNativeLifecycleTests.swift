import Foundation
import XCTest
@testable import RorkDevice

final class PocketNativeLifecycleTests: XCTestCase {
    func testMalformedStatusCannotClaimCleanup() {
        XCTAssertThrowsError(try PocketNativeEngine.mediaSessionIsAbsent(.dictionary([:]), id: Data()))
        XCTAssertThrowsError(try PocketNativeEngine.mediaSessionIsAbsent(.dictionary(["running": .bool(true)]), id: Data()))
        XCTAssertThrowsError(try PocketNativeEngine.mediaSessionIsAbsent(.dictionary(["running": .bool(true), "sessions": .array([.dictionary([:])])]), id: Data()))
    }
    func testCleanupRequiresExactSessionToDisappear() throws {
        let own = Data(repeating: 1, count: 16), other = Data(repeating: 2, count: 16)
        let session: RemoteXPCValue = .dictionary(["connection": .dictionary(["options": .dictionary([
            "avcMediaStreamOptionClientSessionID": .dictionary(["uuid": .uuid(own)])
        ])])])
        let status: RemoteXPCValue = .dictionary(["running": .bool(true), "sessions": .array([session])])
        XCTAssertFalse(try PocketNativeEngine.mediaSessionIsAbsent(status, id: own))
        XCTAssertTrue(try PocketNativeEngine.mediaSessionIsAbsent(status, id: other))
        XCTAssertTrue(try PocketNativeEngine.mediaSessionIsAbsent(.dictionary(["running": .bool(false)]), id: own))
    }
}
