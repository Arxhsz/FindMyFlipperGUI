import XCTest
@testable import FindMyFlipperMac

@MainActor
final class ProfileStoreTests: XCTestCase {
    var sut: ProfileStore!
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = ProfileStore(containerURL: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeProfile(name: String = "Test Flipper", isActive: Bool = false) -> FlipperProfile {
        FlipperProfile(
            id: UUID(), displayName: name, createdAt: Date(), updatedAt: Date(),
            findMyKeyID: UUID(), bleDeviceID: nil,
            generatedFindMyMac: "AA:BB:CC:DD:EE:FF",
            payloadPreview: "preview", hashedAdvKeyPreview: "hash",
            lastReport: nil, lastBLEConnection: nil, batteryLevel: nil,
            isBLEConnected: false, autoReconnect: true,
            refreshInterval: .fifteenMin, isActive: isActive
        )
    }

    func makeKeyRecord() -> FindMyKeyRecord {
        FindMyKeyRecord(
            id: UUID(), displayName: "Test Key", sourceFileName: "test.keys",
            importedAt: Date(), advertisementKeyBase64: nil, advertisementKeyHex: nil,
            hashedAdvKeyBase64: "dGVzdGhhc2g=", generatedFindMyMac: "AA:BB:CC:DD:EE:FF",
            payload: "dGVzdA==", keychainKeyID: UUID()
        )
    }

    func testSaveProfile() throws {
        let p = makeProfile()
        try sut.saveProfile(p)
        XCTAssertEqual(sut.profiles.count, 1)
    }

    func testSetActiveIsExclusive() throws {
        let p1 = makeProfile(name: "P1"); let p2 = makeProfile(name: "P2"); let p3 = makeProfile(name: "P3")
        try sut.saveProfile(p1); try sut.saveProfile(p2); try sut.saveProfile(p3)
        try sut.setActive(profileID: p2.id)
        let actives = sut.profiles.filter { $0.isActive }
        XCTAssertEqual(actives.count, 1)
        XCTAssertEqual(actives[0].id, p2.id)
    }

    func testSetActiveNonExistentThrows() {
        XCTAssertThrowsError(try sut.setActive(profileID: UUID()))
    }

    func testDeleteProfile() throws {
        let p = makeProfile()
        try sut.saveProfile(p)
        try sut.deleteProfile(id: p.id)
        XCTAssertTrue(sut.profiles.isEmpty)
    }

    func testDeletingActiveProfilePromotesAReplacement() throws {
        let active = makeProfile(name: "Active", isActive: true)
        let replacement = makeProfile(name: "Replacement")
        try sut.saveProfile(active)
        try sut.saveProfile(replacement)

        try sut.deleteProfile(id: active.id)

        XCTAssertEqual(sut.activeProfile()?.id, replacement.id)
    }

    func testSaveAndLoadKeyRecord() throws {
        let r = makeKeyRecord()
        try sut.saveKeyRecord(r)
        let loaded = try sut.loadKeyRecord(id: r.id)
        XCTAssertEqual(loaded.keychainKeyID, r.keychainKeyID)
    }

    func testRelinkActiveProfileUsesNewestImportedKeyAndPreservesBLEIdentity() throws {
        var profile = makeProfile(isActive: true)
        let bleID = UUID()
        profile.bleDeviceID = bleID
        try sut.saveProfile(profile)
        let record = makeKeyRecord()
        try sut.saveKeyRecord(record)

        let updated = try sut.relinkActiveProfile(to: record)

        XCTAssertEqual(updated.findMyKeyID, record.id)
        XCTAssertEqual(updated.generatedFindMyMac, record.generatedFindMyMac)
        XCTAssertEqual(updated.bleDeviceID, bleID)
        XCTAssertEqual(sut.activeProfile()?.findMyKeyID, record.id)
    }

    func testPersistenceAcrossReload() throws {
        let p = makeProfile(name: "Persist Me")
        try sut.saveProfile(p)
        let store2 = ProfileStore(containerURL: tempDir)
        XCTAssertEqual(store2.profiles.count, 1)
        XCTAssertEqual(store2.profiles[0].displayName, "Persist Me")
    }

    func testNewestKeyAndUnreferencedCleanupPreserveProfileKey() throws {
        let older = makeKeyRecord()
        var newer = makeKeyRecord()
        newer.importedAt = older.importedAt.addingTimeInterval(60)
        var profile = makeProfile(isActive: true)
        profile.findMyKeyID = newer.id
        try sut.saveKeyRecord(older)
        try sut.saveKeyRecord(newer)
        try sut.saveProfile(profile)

        XCTAssertEqual(sut.keyRecordsNewestFirst.first?.id, newer.id)
        let removed = try sut.removeUnreferencedKeyRecords()

        XCTAssertEqual(removed.map(\.id), [older.id])
        XCTAssertNoThrow(try sut.loadKeyRecord(id: newer.id))
        XCTAssertThrowsError(try sut.loadKeyRecord(id: older.id))
    }

    func testActiveExclusivityWithManyProfiles() throws {
        let ids: [UUID] = try (0..<10).map { i in
            let p = makeProfile(name: "P\(i)")
            try sut.saveProfile(p)
            return p.id
        }
        for targetID in ids {
            try sut.setActive(profileID: targetID)
            let actives = sut.profiles.filter { $0.isActive }
            XCTAssertEqual(actives.count, 1)
            XCTAssertEqual(actives[0].id, targetID)
        }
    }
}
