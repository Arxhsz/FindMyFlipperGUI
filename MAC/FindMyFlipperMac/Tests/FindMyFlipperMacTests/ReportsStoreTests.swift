import XCTest
@testable import FindMyFlipperMac

@MainActor
final class ReportsStoreTests: XCTestCase {
    var sut: ReportsStore!
    var tempDir: URL!
    let profileID = UUID()

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReportsStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = ReportsStore(containerURL: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeReport(id: String = UUID().uuidString, timestamp: TimeInterval = Date().timeIntervalSince1970,
                    lat: Double = 37.3, lon: Double = -122.0, confidence: Int = 75) -> LocationReport {
        LocationReport(id: id, timestamp: timestamp, isoDateTime: "2024-01-01T00:00:00Z",
                       lat: lat, lon: lon, confidence: confidence, status: 0,
                       source: "Find My Network", profileID: profileID)
    }

    func testInsertAndRetrieve() throws {
        let r = makeReport()
        try sut.insert([r], forProfile: profileID)
        XCTAssertEqual(sut.reports(forProfile: profileID).count, 1)
    }

    func testDeduplicationByID() throws {
        let r = makeReport(id: "dup-id")
        try sut.insert([r, r, r], forProfile: profileID)
        XCTAssertEqual(sut.reports(forProfile: profileID).count, 1)
    }

    func testInsertNewReportsPreservesExisting() throws {
        let r1 = makeReport(id: "r1")
        let r2 = makeReport(id: "r2")
        try sut.insert([r1], forProfile: profileID)
        try sut.insert([r2], forProfile: profileID)
        let all = sut.reports(forProfile: profileID)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.id == "r1" })
        XCTAssertTrue(all.contains { $0.id == "r2" })
    }

    func testCapacityBound() throws {
        let reports = (0..<10_001).map { makeReport(id: "r\($0)", timestamp: Double($0)) }
        try sut.insert(reports, forProfile: profileID)
        XCTAssertLessThanOrEqual(sut.reports(forProfile: profileID).count, ReportsStore.maxReportsPerProfile)
    }

    func testOldestArePrunedFirst() throws {
        // Insert 10001 reports with ascending timestamps
        let reports = (0..<10_001).map { makeReport(id: "r\($0)", timestamp: Double($0)) }
        try sut.insert(reports, forProfile: profileID)
        let remaining = sut.reports(forProfile: profileID)
        // Most recent should be kept (highest timestamps)
        let minTimestamp = remaining.map { $0.timestamp }.min() ?? 0
        XCTAssertGreaterThan(minTimestamp, 0, "Oldest reports should have been pruned")
    }

    func testFilterHighAccuracy() throws {
        let low = makeReport(id: "low", confidence: 50)
        let high = makeReport(id: "high", confidence: 80)
        try sut.insert([low, high], forProfile: profileID)
        let filtered = sut.reports(forProfile: profileID, filter: .highAccuracy)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].id, "high")
    }

    func testPersistenceAcrossReload() throws {
        let r = makeReport(id: "persist-me")
        try sut.insert([r], forProfile: profileID)
        let store2 = ReportsStore(containerURL: tempDir)
        XCTAssertEqual(store2.reports(forProfile: profileID).count, 1)
    }

    func testClearReports() throws {
        let r = makeReport()
        try sut.insert([r], forProfile: profileID)
        try sut.clearReports(forProfile: profileID)
        XCTAssertEqual(sut.reports(forProfile: profileID).count, 0)
    }
}
