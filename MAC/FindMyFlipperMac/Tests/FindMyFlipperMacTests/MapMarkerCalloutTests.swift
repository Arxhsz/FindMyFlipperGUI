import AppKit
import SwiftUI
import XCTest
@testable import FindMyFlipperMac

@MainActor
final class MapMarkerCalloutTests: XCTestCase {
    func testCalloutRendersWithoutApplicationEnvironmentObjects() {
        let report = LocationReport(
            id: "render-test",
            timestamp: Date().timeIntervalSince1970,
            isoDateTime: "2026-07-10T18:00:00Z",
            lat: 37.3319,
            lon: -122.0300,
            confidence: 75,
            status: 0,
            source: "Find My Network",
            profileID: UUID()
        )
        let view = MapMarkerCallout(
            report: report,
            profileName: "Test Flipper",
            batteryLevel: 80,
            locationName: "Cupertino, CA",
            iconStyle: .white
        )

        let host = NSHostingView(rootView: view)
        let size = host.fittingSize

        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }
}
