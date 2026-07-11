import XCTest
import Foundation
@testable import FindMyFlipperMac

// MARK: - Random generators for property tests

private func randomString(length: Int = Int.random(in: 1...40)) -> String {
    let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-."
    return String((0..<length).map { _ in chars.randomElement()! })
}

private func randomDate() -> Date {
    // Timestamps in a reasonable range: 2000-01-01 to 2030-01-01
    Date(timeIntervalSince1970: Double.random(in: 946_684_800...1_893_456_000))
}

private func randomLocationReport(profileID: UUID) -> LocationReport {
    LocationReport(
        id: UUID().uuidString,
        timestamp: Double.random(in: 946_684_800...1_893_456_000),
        isoDateTime: "2024-01-01T00:00:00Z",
        lat: Double.random(in: -90.0...90.0),
        lon: Double.random(in: -180.0...180.0),
        confidence: Int.random(in: 0...100),
        status: Int.random(in: 0...2),
        source: randomString(length: Int.random(in: 1...20)),
        profileID: profileID
    )
}

private func randomRefreshInterval() -> RefreshInterval {
    RefreshInterval.allCases.randomElement()!
}

private func randomFlipperProfile() -> FlipperProfile {
    let id = UUID()
    let includeBLE = Bool.random()
    let includeLastReport = Bool.random()
    let includeLastBLE = Bool.random()
    let includeBattery = Bool.random()

    return FlipperProfile(
        id: id,
        displayName: randomString(length: Int.random(in: 1...50)),
        createdAt: randomDate(),
        updatedAt: randomDate(),
        findMyKeyID: UUID(),
        bleDeviceID: includeBLE ? UUID() : nil,
        generatedFindMyMac: randomString(length: 17),
        payloadPreview: randomString(length: Int.random(in: 0...80)),
        hashedAdvKeyPreview: randomString(length: Int.random(in: 0...60)),
        lastReport: includeLastReport ? randomLocationReport(profileID: id) : nil,
        lastBLEConnection: includeLastBLE ? randomDate() : nil,
        batteryLevel: includeBattery ? Int.random(in: 0...100) : nil,
        isBLEConnected: Bool.random(),
        autoReconnect: Bool.random(),
        refreshInterval: randomRefreshInterval(),
        isActive: Bool.random()
    )
}

// MARK: -

final class ModelTests: XCTestCase {

    // MARK: - Property 9: FlipperProfile Codable Round-Trip
    // Validates: Requirements 6.1, 6.4

    /// Generates 100 random FlipperProfile instances, encodes each to JSON, decodes, and asserts equality.
    func testProperty9_FlipperProfileCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        for iteration in 1...100 {
            let profile = randomFlipperProfile()
            let data = try encoder.encode(profile)
            let decoded = try decoder.decode(FlipperProfile.self, from: data)
            XCTAssertEqual(decoded, profile,
                "FlipperProfile Codable round-trip failed on iteration \(iteration). Profile id: \(profile.id)")
        }
    }

    // MARK: - FlipperProfile Codable Round-Trip (fixed example)

    func testFlipperProfileCodableRoundTrip() throws {
        let profile = FlipperProfile(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!,
            displayName: "My Flipper Zero",
            createdAt: Date(timeIntervalSince1970: 1_710_028_800),
            updatedAt: Date(timeIntervalSince1970: 1_710_032_400),
            findMyKeyID: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000002")!,
            bleDeviceID: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000003"),
            generatedFindMyMac: "DE:AD:BE:EF:CA:FE",
            payloadPreview: "AQID...(truncated)",
            hashedAdvKeyPreview: "abc123...(truncated)",
            lastReport: LocationReport(
                id: "report-001",
                timestamp: 1_710_028_800,
                isoDateTime: "2024-03-10T08:00:00Z",
                lat: 37.3319,
                lon: -122.0300,
                confidence: 65,
                status: 0,
                source: "Find My Network",
                profileID: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!
            ),
            lastBLEConnection: Date(timeIntervalSince1970: 1_710_025_200),
            batteryLevel: 72,
            isBLEConnected: true,
            autoReconnect: true,
            refreshInterval: .fifteenMin,
            isActive: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(FlipperProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
    }

    // MARK: - LocationReport Codable Round-Trip

    func testLocationReportCodableRoundTrip() throws {
        let report = LocationReport(
            id: "report-abc-123",
            timestamp: 1_710_028_800,
            isoDateTime: "2024-03-10T08:00:00Z",
            lat: 48.8566,
            lon: 2.3522,
            confidence: 90,
            status: 0,
            source: "Find My Network",
            profileID: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(LocationReport.self, from: data)

        XCTAssertEqual(decoded, report)
    }

    // MARK: - AppSettings Defaults

    func testAppSettingsDefaults() {
        let settings = AppSettings()

        XCTAssertEqual(settings.theme, .light)
        XCTAssertEqual(settings.refreshInterval, .fifteenMin)
        XCTAssertEqual(settings.backendPort, 8765)
        XCTAssertEqual(settings.mapDisplayMode, .standard)
        XCTAssertEqual(settings.flipperIconStyle, .white)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.startInMenuBar)
        XCTAssertFalse(settings.minimizeToMenuBar)
        XCTAssertEqual(settings.accentColor, "#FF5A00")
        XCTAssertEqual(settings.distanceUnit, .metric)
        XCTAssertTrue(settings.notifyOnNewReport)
        XCTAssertTrue(settings.notifyFlipperNearby)
        XCTAssertTrue(settings.notifyLowBattery)
        XCTAssertFalse(settings.debugLogsEnabled)
    }

    // MARK: - DiagnosticID All Cases Count

    func testDiagnosticIDAllCasesCount() {
        XCTAssertEqual(DiagnosticID.allCases.count, 8)
    }

    // MARK: - RefreshInterval Raw Values

    func testRefreshIntervalRawValues() {
        XCTAssertEqual(RefreshInterval.manual.rawValue, 0)
        XCTAssertEqual(RefreshInterval.fiveMin.rawValue, 5)
        XCTAssertEqual(RefreshInterval.fifteenMin.rawValue, 15)
        XCTAssertEqual(RefreshInterval.thirtyMin.rawValue, 30)
    }

    // MARK: - Additional sanity checks

    func testRefreshIntervalDisplayNames() {
        XCTAssertEqual(RefreshInterval.manual.displayName, "Manual only")
        XCTAssertEqual(RefreshInterval.fiveMin.displayName, "5 minutes")
        XCTAssertEqual(RefreshInterval.fifteenMin.displayName, "15 minutes")
        XCTAssertEqual(RefreshInterval.thirtyMin.displayName, "30 minutes")
    }

    func testThemeOptionDisplayNames() {
        XCTAssertEqual(ThemeOption.light.displayName, "Light")
        XCTAssertEqual(ThemeOption.dark.displayName, "Dark")
        XCTAssertEqual(ThemeOption.system.displayName, "System")
        XCTAssertEqual(ThemeOption.allCases.count, 7)
    }

    func testAppSettingsDecodesOldSettingsWithoutNewAppearanceFields() throws {
        let json = """
        {
          "launchAtLogin": true,
          "refreshInterval": 5,
          "theme": "dark",
          "accentColor": "#FF5A00",
          "distanceUnit": "imperial",
          "backendPort": 8765
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertEqual(settings.refreshInterval, .fiveMin)
        XCTAssertEqual(settings.theme, .dark)
        XCTAssertEqual(settings.distanceUnit, .imperial)
        XCTAssertEqual(settings.mapDisplayMode, .standard)
        XCTAssertEqual(settings.flipperIconStyle, .white)
        XCTAssertTrue(settings.notifyOnNewReport)
        XCTAssertTrue(settings.notifyFlipperNearby)
        XCTAssertTrue(settings.notifyLowBattery)
    }

    func testMapDisplayModeCyclesThroughAllModes() {
        XCTAssertEqual(MapDisplayMode.standard.next, .hybrid)
        XCTAssertEqual(MapDisplayMode.hybrid.next, .imagery)
        XCTAssertEqual(MapDisplayMode.imagery.next, .standard)
    }

    func testLocationReportCoordinateProperties() {
        let report = LocationReport(
            id: "coord-test",
            timestamp: 0,
            isoDateTime: "2024-01-01T00:00:00Z",
            lat: 51.5074,
            lon: -0.1278,
            confidence: 80,
            status: 0,
            source: "test",
            profileID: UUID()
        )
        XCTAssertEqual(report.coordinate.latitude, 51.5074, accuracy: 0.0001)
        XCTAssertEqual(report.coordinate.longitude, -0.1278, accuracy: 0.0001)
    }

    func testBLEDeviceScoreAllCases() {
        XCTAssertEqual(BLEDeviceScore.allCases.count, 4)
        XCTAssertTrue(BLEDeviceScore.allCases.contains(.recommended))
        XCTAssertTrue(BLEDeviceScore.allCases.contains(.possibleFlipper))
        XCTAssertTrue(BLEDeviceScore.allCases.contains(.unknown))
        XCTAssertTrue(BLEDeviceScore.allCases.contains(.weak))
    }

    // MARK: - Property 6: Decrypted Report Coordinates Are Within Valid Geographic Ranges
    // Validates: Requirements 5.4

    /// Generates a random LocationReportDTO using the same structure as the backend decode path,
    /// converts it to a LocationReport, and asserts all coordinate and confidence values are
    /// within valid geographic ranges: lat in -90...90, lon in -180...180, confidence in 0...100.
    func testLocationReportDTOCoordinateRangesPropertyTest() {
        // Custom random generator — no third-party PBT library required (see design doc notes)
        var rng = SystemRandomNumberGenerator()

        func randomDouble(in range: ClosedRange<Double>, using rng: inout SystemRandomNumberGenerator) -> Double {
            let span = range.upperBound - range.lowerBound
            let fraction = Double(rng.next()) / Double(UInt64.max)
            return range.lowerBound + fraction * span
        }

        func randomInt(in range: ClosedRange<Int>, using rng: inout SystemRandomNumberGenerator) -> Int {
            let span = range.upperBound - range.lowerBound
            return range.lowerBound + Int(rng.next() % UInt64(span + 1))
        }

        let profileID = UUID()
        let iterations = 500

        for i in 0..<iterations {
            // Simulate the backend decode path: lat/lon are int32 values scaled by 1e7 (range ±90° / ±180°)
            // The decryptor scales raw int32 lat by 1e7, so the double result must be in -90...90 / -180...180
            let rawLat = randomInt(in: -900_000_000...900_000_000, using: &rng)
            let rawLon = randomInt(in: -1_800_000_000...1_800_000_000, using: &rng)
            let lat = Double(rawLat) / 1e7
            let lon = Double(rawLon) / 1e7

            // confidence is a single byte in the decrypted payload: 0...100
            let confidence = randomInt(in: 0...100, using: &rng)

            let dto = LocationReportDTO(
                id: "prop-test-\(i)",
                timestamp: TimeInterval(randomInt(in: 0...2_000_000_000, using: &rng)),
                isoDateTime: "2024-01-01T00:00:00Z",
                lat: lat,
                lon: lon,
                confidence: confidence,
                status: 0,
                source: "Find My Network"
            )

            let report = dto.toLocationReport(profileID: profileID)

            XCTAssertGreaterThanOrEqual(
                report.lat, -90.0,
                "Iteration \(i): lat \(report.lat) is below -90.0 (out of range)"
            )
            XCTAssertLessThanOrEqual(
                report.lat, 90.0,
                "Iteration \(i): lat \(report.lat) exceeds 90.0 (out of range)"
            )
            XCTAssertGreaterThanOrEqual(
                report.lon, -180.0,
                "Iteration \(i): lon \(report.lon) is below -180.0 (out of range)"
            )
            XCTAssertLessThanOrEqual(
                report.lon, 180.0,
                "Iteration \(i): lon \(report.lon) exceeds 180.0 (out of range)"
            )
            XCTAssertGreaterThanOrEqual(
                report.confidence, 0,
                "Iteration \(i): confidence \(report.confidence) is below 0"
            )
            XCTAssertLessThanOrEqual(
                report.confidence, 100,
                "Iteration \(i): confidence \(report.confidence) exceeds 100"
            )

            // Verify toLocationReport preserves all fields correctly
            XCTAssertEqual(report.lat, dto.lat, "Iteration \(i): lat not preserved by toLocationReport")
            XCTAssertEqual(report.lon, dto.lon, "Iteration \(i): lon not preserved by toLocationReport")
            XCTAssertEqual(report.confidence, dto.confidence, "Iteration \(i): confidence not preserved")
            XCTAssertEqual(report.profileID, profileID, "Iteration \(i): profileID not set correctly")
        }
    }

    /// Boundary test: exercises the exact edge values of each range to confirm
    /// the model accepts valid boundary values and the constraints hold exactly.
    func testLocationReportDTOCoordinateRangeBoundaries() {
        let profileID = UUID()

        let boundaries: [(lat: Double, lon: Double, confidence: Int, label: String)] = [
            (lat: -90.0, lon: -180.0, confidence: 0,   label: "min boundaries"),
            (lat:  90.0, lon:  180.0, confidence: 100,  label: "max boundaries"),
            (lat:   0.0, lon:    0.0, confidence: 50,   label: "zero/midpoint"),
            (lat: -90.0, lon:  180.0, confidence: 0,   label: "mixed min/max"),
            (lat:  90.0, lon: -180.0, confidence: 100,  label: "mixed max/min"),
        ]

        for boundary in boundaries {
            let dto = LocationReportDTO(
                id: "boundary-\(boundary.label)",
                timestamp: 0,
                isoDateTime: "2024-01-01T00:00:00Z",
                lat: boundary.lat,
                lon: boundary.lon,
                confidence: boundary.confidence,
                status: 0,
                source: "test"
            )
            let report = dto.toLocationReport(profileID: profileID)

            XCTAssertTrue(
                (-90.0...90.0).contains(report.lat),
                "Boundary '\(boundary.label)': lat \(report.lat) not in -90...90"
            )
            XCTAssertTrue(
                (-180.0...180.0).contains(report.lon),
                "Boundary '\(boundary.label)': lon \(report.lon) not in -180...180"
            )
            XCTAssertTrue(
                (0...100).contains(report.confidence),
                "Boundary '\(boundary.label)': confidence \(report.confidence) not in 0...100"
            )
        }
    }
}
