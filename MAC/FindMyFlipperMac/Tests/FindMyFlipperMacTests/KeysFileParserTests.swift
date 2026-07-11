import XCTest
import Foundation
@testable import FindMyFlipperMac

// MARK: - Random generators

private func randomBase64String(byteCount: Int = Int.random(in: 16...44)) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    for i in 0..<byteCount { bytes[i] = UInt8.random(in: 0...255) }
    return Data(bytes).base64EncodedString()
}

private func randomHexString(byteCount: Int = Int.random(in: 16...32)) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    for i in 0..<byteCount { bytes[i] = UInt8.random(in: 0...255) }
    return bytes.map { String(format: "%02x", $0) }.joined()
}

private func randomMAC() -> String {
    (0..<6).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined(separator: ":")
}

/// Builds a valid `.keys` file string with all required fields present and non-empty.
/// Optional fields are included randomly.
private func randomValidKeysContent() -> (
    content: String,
    privateKey: String,
    hashedAdvKey: String,
    mac: String,
    payload: String
) {
    let privateKey   = randomBase64String(byteCount: 28)
    let hashedAdvKey = randomBase64String(byteCount: 28)
    let mac          = randomMAC()
    let payload      = randomBase64String(byteCount: Int.random(in: 32...64))

    var lines = [
        "Private key: \(privateKey)",
        "Hashed adv key: \(hashedAdvKey)",
        "MAC: \(mac)",
        "Payload: \(payload)"
    ]

    // Optional fields — include randomly to vary the file shape
    if Bool.random() { lines.append("Private key (Hex): \(randomHexString())") }
    if Bool.random() { lines.append("Advertisement key: \(randomBase64String())") }
    if Bool.random() { lines.append("Advertisement key (Hex): \(randomHexString())") }

    // Shuffle to assert parser is order-independent
    lines.shuffle()
    return (lines.joined(separator: "\n"), privateKey, hashedAdvKey, mac, payload)
}

// MARK: - KeysFileParserTests

final class KeysFileParserTests: XCTestCase {

    private let parser = KeysFileParser()
    private let requiredFields = ["Private key", "Hashed adv key", "MAC", "Payload"]

    // MARK: - Property 1: Keys File Parse Succeeds for All Valid Files
    // Validates: Requirements 2.1, 2.2

    /// For 200 randomly generated valid `.keys` file strings (all required fields present),
    /// asserts that `isValid == true` and that all non-private fields are non-empty.
    func testProperty1_ParseSucceedsForAllValidFiles() {
        for iteration in 1...200 {
            let (content, _, hashedAdvKey, mac, payload) = randomValidKeysContent()
            let result = parser.parseContent(content, sourceFileName: "flipper-\(iteration).keys")

            XCTAssertTrue(
                result.isValid,
                "Iteration \(iteration): expected isValid==true but got errors: \(result.validationErrors.map(\.message))"
            )
            XCTAssertFalse(
                result.privateKeyBase64.isEmpty,
                "Iteration \(iteration): privateKeyBase64 should not be empty for a valid file"
            )
            XCTAssertFalse(
                result.record.hashedAdvKeyBase64.isEmpty,
                "Iteration \(iteration): hashedAdvKeyBase64 should not be empty"
            )
            XCTAssertFalse(
                result.record.generatedFindMyMac.isEmpty,
                "Iteration \(iteration): generatedFindMyMac should not be empty"
            )
            XCTAssertFalse(
                result.record.payload.isEmpty,
                "Iteration \(iteration): payload should not be empty"
            )
            // Sanity-check the values match what we generated
            XCTAssertEqual(result.record.hashedAdvKeyBase64, hashedAdvKey, "Iteration \(iteration): hashedAdvKey mismatch")
            XCTAssertEqual(result.record.generatedFindMyMac, mac, "Iteration \(iteration): MAC mismatch")
            XCTAssertEqual(result.record.payload, payload, "Iteration \(iteration): payload mismatch")
        }
    }

    // MARK: - Property 2: Keys File Parse Rejects Any File Missing a Required Field
    // Validates: Requirements 2.3, 2.4

    /// For each of the 4 required fields, generates 50 files with that single field omitted and
    /// asserts that `isValid == false` and that a `KeysValidationError` naming that field is present.
    func testProperty2_ParseRejectsFileMissingRequiredField() {
        for missingField in requiredFields {
            for iteration in 1...50 {
                // Build a full set of fields then drop the target one
                let allFields: [String: String] = [
                    "Private key":   randomBase64String(byteCount: 28),
                    "Hashed adv key": randomBase64String(byteCount: 28),
                    "MAC":           randomMAC(),
                    "Payload":       randomBase64String(byteCount: 32)
                ]

                let lines = allFields.compactMap { key, value -> String? in
                    key == missingField ? nil : "\(key): \(value)"
                }
                let content = lines.joined(separator: "\n")
                let result  = parser.parseContent(content, sourceFileName: "missing-\(iteration).keys")

                XCTAssertFalse(
                    result.isValid,
                    "Missing '\(missingField)', iteration \(iteration): expected isValid==false"
                )
                XCTAssertFalse(
                    result.validationErrors.isEmpty,
                    "Missing '\(missingField)', iteration \(iteration): expected at least one validation error"
                )
                let affectsField = result.validationErrors.contains { $0.field == missingField }
                XCTAssertTrue(
                    affectsField,
                    "Missing '\(missingField)', iteration \(iteration): expected error for field '\(missingField)', got \(result.validationErrors.map(\.field))"
                )
            }
        }
    }

    /// Extra: all four fields absent at once should produce exactly four errors.
    func testProperty2_AllRequiredFieldsMissingProducesFourErrors() {
        let result = parser.parseContent("", sourceFileName: "empty.keys")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.validationErrors.count, 4,
            "Expected 4 validation errors for a completely empty file, got \(result.validationErrors.count)")
        for field in requiredFields {
            XCTAssertTrue(
                result.validationErrors.contains { $0.field == field },
                "Expected error for required field '\(field)' when file is empty"
            )
        }
    }

    // MARK: - Property 3: Private Key Is Never Stored Outside the Keychain
    // Validates: Requirements 2.6, 9.1, 9.2

    /// For 200 random valid `.keys` files, asserts that the returned `FindMyKeyRecord` contains
    /// no private key field whatsoever — the private key is returned separately and must not leak
    /// into the persistent record.
    func testProperty3_PrivateKeyNeverStoredInRecord() {
        // Confirm at compile-time that FindMyKeyRecord has no private key field by inspecting
        // all stored String / Optional<String> properties via reflection (Mirror).
        for iteration in 1...200 {
            let (content, privateKey, _, _, _) = randomValidKeysContent()
            let result = parser.parseContent(content, sourceFileName: "pk-test-\(iteration).keys")

            XCTAssertTrue(result.isValid, "Iteration \(iteration): file should be valid")

            // Use Mirror to enumerate all stored properties on FindMyKeyRecord
            let mirror = Mirror(reflecting: result.record)
            for child in mirror.children {
                let label = child.label ?? "(unknown)"
                // Check String values
                if let strVal = child.value as? String {
                    XCTAssertNotEqual(
                        strVal, privateKey,
                        "Iteration \(iteration): private key found in record field '\(label)'"
                    )
                }
                // Check Optional<String> values
                if let optStrVal = child.value as? String? {
                    if let unwrapped = optStrVal {
                        XCTAssertNotEqual(
                            unwrapped, privateKey,
                            "Iteration \(iteration): private key found in optional record field '\(label)'"
                        )
                    }
                }
            }

            // The private key lives in KeysParseResult.privateKeyBase64 — confirm it's accessible there
            XCTAssertEqual(
                result.privateKeyBase64, privateKey,
                "Iteration \(iteration): privateKeyBase64 on result should equal the input private key"
            )
        }
    }

    // MARK: - Property 11: Non-Private Keys File Fields Round-Trip Through Parse
    // Validates: Requirements 2.1, 2.2, 5.1

    /// Parses 200 randomly generated `.keys` files and asserts that `hashedAdvKeyBase64`,
    /// `generatedFindMyMac`, and `payload` on the returned record exactly equal the values
    /// that were written into the file.
    func testProperty11_NonPrivateFieldsRoundTripThroughParse() {
        for iteration in 1...200 {
            let (content, _, hashedAdvKey, mac, payload) = randomValidKeysContent()
            let fileName = "round-trip-\(iteration).keys"
            let result   = parser.parseContent(content, sourceFileName: fileName)

            XCTAssertTrue(result.isValid,
                "Iteration \(iteration): expected valid parse, errors: \(result.validationErrors.map(\.message))")

            XCTAssertEqual(
                result.record.hashedAdvKeyBase64, hashedAdvKey,
                "Iteration \(iteration): hashedAdvKeyBase64 did not round-trip"
            )
            XCTAssertEqual(
                result.record.generatedFindMyMac, mac,
                "Iteration \(iteration): generatedFindMyMac (MAC) did not round-trip"
            )
            XCTAssertEqual(
                result.record.payload, payload,
                "Iteration \(iteration): payload did not round-trip"
            )

            // sourceFileName should be preserved on the record
            XCTAssertEqual(
                result.record.sourceFileName, fileName,
                "Iteration \(iteration): sourceFileName was not preserved"
            )
            // displayName derived from file name (without extension)
            let expectedDisplayName = (fileName as NSString).deletingPathExtension
            XCTAssertEqual(
                result.record.displayName, expectedDisplayName,
                "Iteration \(iteration): displayName was not derived correctly from fileName"
            )
        }
    }

    // MARK: - Additional unit tests (fixed examples)

    func testParseValidFile_fixedExample() {
        let content = """
        Private key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        Hashed adv key: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
        MAC: 11:22:33:44:55:66
        Payload: CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
        """
        let result = parser.parseContent(content, sourceFileName: "flipper.keys")
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.privateKeyBase64, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(result.record.hashedAdvKeyBase64, "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
        XCTAssertEqual(result.record.generatedFindMyMac, "11:22:33:44:55:66")
        XCTAssertEqual(result.record.payload, "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC")
        XCTAssertEqual(result.record.displayName, "flipper")
        XCTAssertEqual(result.record.sourceFileName, "flipper.keys")
    }

    func testParseIsCaseInsensitiveForFieldNames() {
        let content = """
        PRIVATE KEY: myPrivKey
        HASHED ADV KEY: myHashedKey
        mac: AA:BB:CC:DD:EE:FF
        PAYLOAD: myPayload
        """
        let result = parser.parseContent(content, sourceFileName: "upper.keys")
        XCTAssertTrue(result.isValid, "Parser should be case-insensitive; errors: \(result.validationErrors.map(\.message))")
        XCTAssertEqual(result.privateKeyBase64, "myPrivKey")
        XCTAssertEqual(result.record.hashedAdvKeyBase64, "myHashedKey")
        XCTAssertEqual(result.record.generatedFindMyMac, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(result.record.payload, "myPayload")
    }

    func testParseAcceptsBase64FieldAliases() {
        let content = """
        Private key (Base64): myPrivKey
        Hashed adv key (Base64): myHashedKey
        MAC: AA:BB:CC:DD:EE:FF
        Payload: myPayload
        Advertisement key (Base64): myAdvertisementKey
        """
        let result = parser.parseContent(content, sourceFileName: "aliases.keys")
        XCTAssertTrue(result.isValid, "Parser should accept original-compatible Base64 aliases; errors: \(result.validationErrors.map(\.message))")
        XCTAssertEqual(result.privateKeyBase64, "myPrivKey")
        XCTAssertEqual(result.record.hashedAdvKeyBase64, "myHashedKey")
        XCTAssertEqual(result.record.advertisementKeyBase64, "myAdvertisementKey")
    }

    func testParseDisplayNameDefaultsToFlipperZeroForEmptyExtensionlessName() {
        let result = parser.parseContent("", sourceFileName: ".keys")
        // nameWithoutExtension of ".keys" is "" — should default to "Flipper Zero"
        XCTAssertEqual(result.record.displayName, "Flipper Zero")
    }

    func testParseSingleMissingFieldProducesOneError() {
        let content = """
        Private key: someKey
        Hashed adv key: someHash
        Payload: somePayload
        """
        // MAC is missing
        let result = parser.parseContent(content, sourceFileName: "no-mac.keys")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.validationErrors.count, 1)
        XCTAssertEqual(result.validationErrors.first?.field, "MAC")
    }

    func testParseValueWithColonPreservesRemainder() {
        // Values that themselves contain colons (e.g. MAC-like payloads)
        let content = """
        Private key: abc
        Hashed adv key: def
        MAC: 11:22:33:44:55:66
        Payload: base64+with/chars==
        """
        let result = parser.parseContent(content, sourceFileName: "colons.keys")
        XCTAssertTrue(result.isValid)
        // First colon splits correctly — MAC value should be "11:22:33:44:55:66"
        XCTAssertEqual(result.record.generatedFindMyMac, "11:22:33:44:55:66")
    }
}
