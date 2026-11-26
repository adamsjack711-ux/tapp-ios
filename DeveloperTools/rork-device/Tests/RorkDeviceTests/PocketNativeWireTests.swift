import Foundation
import XCTest
@testable import RorkDevice

final class PocketNativeWireTests: XCTestCase {
    func testHomeButtonHasOnlyFixedHomeUsageAndCorrectWireStates() {
        for pressed in [true, false] {
            let event = PocketNativeWire.homeButton(pressed: pressed).dictionaryValue
            XCTAssertEqual(event?["messageType"], .string("IndigoButtonEvent"))
            XCTAssertEqual(event?["featureIdentifier"], .string("com.apple.coredevice.feature.remote.hid.button"))
            XCTAssertEqual(event?["payload"], .dictionary([
                "usagePage": .uint64(12), "usageCode": .uint64(64), "state": .uint64(pressed ? 1 : 2)
            ]))
        }
    }
    func testNavigationHasOnlyFixedBoundedPathsAndSwitcherPause() throws {
        XCTAssertEqual(PocketNavigationGesture.home.homeButtonPressCount, 1)
        XCTAssertEqual(PocketNavigationGesture.appSwitcher.homeButtonPressCount, 2)
        XCTAssertEqual(PocketNavigationGesture.pageLeft.homeButtonPressCount, 0)
        XCTAssertEqual(PocketNavigationGesture.pageRight.homeButtonPressCount, 0)
        XCTAssertEqual(PocketNavigationGesture.home.start.1, 0.995)
        XCTAssertEqual(PocketNavigationGesture.home.holdMilliseconds, 0)
        XCTAssertEqual(PocketNavigationGesture.appSwitcher.holdMilliseconds, 600)
        XCTAssertLessThan(PocketNavigationGesture.pageLeft.end.0, PocketNavigationGesture.pageLeft.start.0)
        XCTAssertGreaterThan(PocketNavigationGesture.pageRight.end.0, PocketNavigationGesture.pageRight.start.0)
        for gesture in PocketNavigationGesture.allCases {
            for point in [gesture.start, gesture.end] {
                let down = try PocketNativeWire.touch(x: point.0, y: point.1, contact: true, timestamp: 1)
                let up = try PocketNativeWire.touch(x: point.0, y: point.1, contact: false, timestamp: 2)
                XCTAssertEqual(down.count, 58); XCTAssertEqual(up.count, 58)
                XCTAssertEqual(down[3], 0xc2); XCTAssertEqual(up[3], 0x02)
            }
            XCTAssertLessThanOrEqual(12 * 30 + gesture.holdMilliseconds, 1_000)
        }
    }
    func testTouchLayoutAndRelease() throws {
        let down = try PocketNativeWire.touch(x: 0, y: 1, contact: true, timestamp: 0x123456789abc)
        XCTAssertEqual(down.count, 58)
        XCTAssertEqual(Array(down.prefix(8)), [9, 1, 5, 0xc2, 0, 0, 255, 255])
        XCTAssertEqual(Array(down[44..<50]), [0xbc, 0x9a, 0x78, 0x56, 0x34, 0x12])
        XCTAssertEqual(down[40], 2)
        XCTAssertEqual(try PocketNativeWire.touch(x: 0.5, y: 0.5, contact: false, timestamp: 0)[3], 2)
    }
    func testInvalidCoordinatesCannotWrapOrClamp() {
        for x in [-0.1, 1.1, .nan, .infinity] {
            XCTAssertThrowsError(try PocketNativeWire.touch(x: x, y: 0.5, contact: true, timestamp: 0))
            XCTAssertThrowsError(try PocketNativeWire.touch(x: 0.5, y: x, contact: true, timestamp: 0))
        }
    }
    func testStoredZlibKnownVector() {
        XCTAssertEqual(Array(PocketNativeWire.storedZlib(Data("abc".utf8))), [0x78,1,1,3,0,0xfc,0xff,97,98,99,0x02,0x4d,0x01,0x27])
    }
    func testMediaOfferIsBinaryPlistWithVideoOnly() throws {
        let offer = try PocketNativeWire.offer(sessionID: 42)
        XCTAssertTrue(offer.starts(with: Data("bplist00".utf8)))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: offer, format: nil) as? [String: Any])
        XCTAssertEqual(plist["avcMediaStreamNegotiatorMode"] as? Int, 5)
        XCTAssertEqual(plist.count, 4)
        XCTAssertNotNil(plist["avcMediaStreamNegotiatorMediaBlob"] as? Data)
    }
    func testDiscardSinkDoesNotConsumeTCPOrAnotherPort() {
        let sink = PocketNativeMediaSink()
        var packet = Data(repeating: 0, count: 48)
        packet[0] = 0x60; packet[5] = 8; packet[6] = 17
        packet[42] = UInt8(47000 >> 8); packet[43] = UInt8(truncatingIfNeeded: 47000); packet[45] = 8
        XCTAssertTrue(sink.consume(packet))
        packet[6] = 6; XCTAssertFalse(sink.consume(packet))
        packet[6] = 17; packet[43] = 1; XCTAssertFalse(sink.consume(packet))
        XCTAssertEqual(sink.packetsReceived, 1)
    }
}
