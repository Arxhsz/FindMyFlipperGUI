import XCTest
@testable import FindMyFlipperMac

final class BLEDeviceScorerTests: XCTestCase {
    let scorer = BLEDeviceScorer()

    // 1. Flipper name + strong RSSI → recommended
    func testFlipperNameStrongRSSI_Recommended() {
        let result = scorer.score(name: "Flipper Zero", rssi: -60, lastSeen: Date())
        XCTAssertEqual(result, .recommended)
    }

    // 2. FZ name + strong RSSI → recommended
    func testFZNameStrongRSSI_Recommended() {
        let result = scorer.score(name: "FZ-Device", rssi: -60, lastSeen: Date())
        XCTAssertEqual(result, .recommended)
    }

    // 3. Exactly -65 RSSI with Flipper name → recommended (boundary inclusive)
    func testExactlyMinus65RSSI_Recommended() {
        let result = scorer.score(name: "Flipper", rssi: -65, lastSeen: Date())
        XCTAssertEqual(result, .recommended)
    }

    // 4. -66 with Flipper name → possibleFlipper (just below recommended threshold)
    func testMinus66WithFlipperName_PossibleFlipper() {
        let result = scorer.score(name: "Flipper", rssi: -66, lastSeen: Date())
        XCTAssertEqual(result, .possibleFlipper)
    }

    // 5. RSSI < -80 → weak (regardless of name)
    func testRSSIBelowMinus80_Weak() {
        let result = scorer.score(name: nil, rssi: -81, lastSeen: Date())
        XCTAssertEqual(result, .weak)
    }

    // 6. Exactly -80 → NOT weak (boundary: -80 is not < -80)
    func testExactlyMinus80_NotWeak() {
        let result = scorer.score(name: nil, rssi: -80, lastSeen: Date())
        XCTAssertNotEqual(result, .weak)
    }

    // 7. Unknown name + -70 RSSI → possibleFlipper (RSSI >= -75, not a Flipper name)
    func testUnknownNameMinus70RSSI_PossibleFlipper() {
        let result = scorer.score(name: "RandomDevice", rssi: -70, lastSeen: Date())
        XCTAssertEqual(result, .possibleFlipper)
    }

    // 8. Unknown name + -77 RSSI → unknown (RSSI between -80 and -75, no Flipper name)
    func testUnknownNameMinus77RSSI_Unknown() {
        let result = scorer.score(name: "RandomDevice", rssi: -77, lastSeen: Date())
        XCTAssertEqual(result, .unknown)
    }

    // 9. nil name doesn't crash
    func testNilNameDoesNotCrash() {
        let result = scorer.score(name: nil, rssi: -60, lastSeen: Date())
        XCTAssertNotNil(result)
    }

    // 10. Determinism: same inputs produce same output
    func testDeterminism() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        // Use a fixed "now" by passing a recent lastSeen so score doesn't vary by real time
        // We use a date that is guaranteed recent (within 60s for recommended to hold)
        let ref = Date()
        let r1 = scorer.score(name: "Flipper", rssi: -60, lastSeen: ref)
        let r2 = scorer.score(name: "Flipper", rssi: -60, lastSeen: ref)
        XCTAssertEqual(r1, r2)
        _ = date // suppress unused warning
    }

    // 11. Case-insensitive: "FLIPPER ZERO" → recommended
    func testCaseInsensitiveFlipperName_Recommended() {
        let result = scorer.score(name: "FLIPPER ZERO", rssi: -60, lastSeen: Date())
        XCTAssertEqual(result, .recommended)
    }

    // 12. Old timestamp (>60s ago) + Flipper name → NOT recommended
    func testOldTimestampFlipperName_NotRecommended() {
        let oldDate = Date().addingTimeInterval(-61)
        let result = scorer.score(name: "Flipper", rssi: -60, lastSeen: oldDate)
        XCTAssertNotEqual(result, .recommended)
    }
}
