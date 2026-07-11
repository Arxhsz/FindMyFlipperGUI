import XCTest
@testable import FindMyFlipperMac

final class KeychainServiceTests: XCTestCase {
    var sut: KeychainService!
    var testKeyIDs: [UUID] = []

    override func setUp() {
        super.setUp()
        // Use a test-specific service to avoid polluting real Keychain
        sut = KeychainService(service: "com.findmyflipper.mac.tests")
    }

    override func tearDown() {
        // Clean up all test keys
        for id in testKeyIDs {
            try? sut.deletePrivateKey(forID: id)
        }
        testKeyIDs.removeAll()
        super.tearDown()
    }

    func makeTestKey() -> (UUID, String) {
        let id = UUID()
        testKeyIDs.append(id)
        let key = Data(count: 28).base64EncodedString() // 28-byte simulated SECP224R1 key
        return (id, key)
    }

    func testSaveAndLoadRoundTrip() throws {
        let (id, key) = makeTestKey()
        try sut.savePrivateKey(key, forID: id)
        let loaded = try sut.loadPrivateKey(forID: id)
        XCTAssertEqual(loaded, key)
    }

    func testSaveDuplicateThrows() throws {
        let (id, key) = makeTestKey()
        try sut.savePrivateKey(key, forID: id)
        XCTAssertThrowsError(try sut.savePrivateKey(key, forID: id)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.duplicateItem)
        }
    }

    func testLoadNonExistentThrows() {
        let id = UUID()
        testKeyIDs.append(id)
        XCTAssertThrowsError(try sut.loadPrivateKey(forID: id)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.itemNotFound)
        }
    }

    func testDeleteExistingKey() throws {
        let (id, key) = makeTestKey()
        try sut.savePrivateKey(key, forID: id)
        XCTAssertTrue(sut.privateKeyExists(forID: id))
        try sut.deletePrivateKey(forID: id)
        XCTAssertFalse(sut.privateKeyExists(forID: id))
    }

    func testDeleteNonExistentThrows() {
        let id = UUID()
        testKeyIDs.append(id)
        XCTAssertThrowsError(try sut.deletePrivateKey(forID: id)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.itemNotFound)
        }
    }

    func testPrivateKeyExistsReturnsFalseForMissing() {
        let id = UUID()
        testKeyIDs.append(id)
        XCTAssertFalse(sut.privateKeyExists(forID: id))
    }

    // Property test: round-trip with varied key strings
    func testRoundTripWithVariousKeyLengths() throws {
        let testCases = [
            Data(count: 28).base64EncodedString(),
            Data(count: 32).base64EncodedString(),
            Data(repeating: 0xFF, count: 28).base64EncodedString(),
        ]
        for keyString in testCases {
            let id = UUID()
            testKeyIDs.append(id)
            try sut.savePrivateKey(keyString, forID: id)
            let loaded = try sut.loadPrivateKey(forID: id)
            XCTAssertEqual(loaded, keyString, "Round-trip failed for key: \(keyString)")
        }
    }

    // MARK: - Property 4: Keychain Private Key Round-Trip
    //
    // Validates: Requirements 3.1, 9.3
    //
    // For any valid Base64-encoded private key string and any UUID key identifier,
    // saving the key with savePrivateKey(_:forID:) and then loading it with
    // loadPrivateKey(forID:) SHALL return a string equal to the original input.

    func testPropertyKeychainRoundTrip() throws {
        // Run 50 iterations with random Base64 keys of varying lengths and content
        for _ in 0..<50 {
            let (id, key) = makeRandomBase64Key()
            testKeyIDs.append(id)
            try sut.savePrivateKey(key, forID: id)
            let loaded = try sut.loadPrivateKey(forID: id)
            XCTAssertEqual(
                loaded, key,
                "Property 4 violation: round-trip failed — loaded key does not equal saved key"
            )
        }
    }

    func testPropertyKeychainRoundTripDeletedKeyNotFound() throws {
        // After saving and deleting, loading must throw itemNotFound (cleanup invariant)
        for _ in 0..<20 {
            let (id, key) = makeRandomBase64Key()
            testKeyIDs.append(id)
            try sut.savePrivateKey(key, forID: id)
            try sut.deletePrivateKey(forID: id)
            // Remove from cleanup list since we already deleted it
            testKeyIDs.removeAll { $0 == id }
            XCTAssertThrowsError(try sut.loadPrivateKey(forID: id)) { error in
                XCTAssertEqual(
                    error as? KeychainError,
                    KeychainError.itemNotFound,
                    "Property 4 violation: deleted key should not be loadable"
                )
            }
        }
    }

    func testPropertyKeychainRoundTripMultipleKeysAreIndependent() throws {
        // Save multiple random keys; each must round-trip independently without interference
        var pairs: [(UUID, String)] = []
        for _ in 0..<10 {
            let (id, key) = makeRandomBase64Key()
            testKeyIDs.append(id)
            try sut.savePrivateKey(key, forID: id)
            pairs.append((id, key))
        }
        for (id, originalKey) in pairs {
            let loaded = try sut.loadPrivateKey(forID: id)
            XCTAssertEqual(
                loaded, originalKey,
                "Property 4 violation: key for id \(id) was corrupted by concurrent saves"
            )
        }
    }

    // MARK: - Helpers

    /// Generates a random UUID and a random Base64-encoded key of a random valid length.
    /// Key byte lengths vary between 16 and 64 bytes (covering SECP224R1 28-byte keys and others).
    private func makeRandomBase64Key() -> (UUID, String) {
        let byteCount = Int.random(in: 16...64)
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount {
            bytes[i] = UInt8.random(in: 0...255)
        }
        let key = Data(bytes).base64EncodedString()
        return (UUID(), key)
    }

    func testDefaultServiceMigratesLegacyBundleIdentifierEntry() throws {
        let legacyService = "com.findmyflipper.mac.legacy-tests-\(UUID().uuidString)"
        let currentService = "com.findmyflipper.mac.current-tests-\(UUID().uuidString)"
        let legacy = KeychainService(service: legacyService)
        let sut = KeychainService(service: currentService, legacyServices: [legacyService])
        let keyID = UUID()
        try legacy.savePrivateKey("legacy-private-key", forID: keyID)
        defer { try? sut.deletePrivateKey(forID: keyID) }

        XCTAssertEqual(try sut.loadPrivateKey(forID: keyID), "legacy-private-key")
        XCTAssertThrowsError(try legacy.loadPrivateKey(forID: keyID))
    }
}
