import Foundation

// MARK: - KeysParseResult

/// The result of parsing a `.keys` file.
/// The `privateKeyBase64` field is ephemeral — the caller must store it
/// in the Keychain immediately and discard this struct.
struct KeysParseResult {
    /// The key record with all non-private fields populated.
    let record: FindMyKeyRecord
    /// Ephemeral private key — store to Keychain immediately.
    let privateKeyBase64: String
    /// Validation errors for missing or empty required fields.
    let validationErrors: [KeysValidationError]
    /// True when all required fields are present and non-empty.
    var isValid: Bool { validationErrors.isEmpty }
}

// MARK: - KeysFileParser

/// Parses a `.keys` file produced by FindMyFlipper into a `KeysParseResult`.
///
/// The `.keys` format is a plain-text `key: value` file where each line
/// contains a field name and its value separated by the first colon.
/// Field names are matched case-insensitively.
struct KeysFileParser {

    // MARK: - Required field names (canonical casing)

    private static let fieldPrivateKey         = "Private key"
    private static let fieldHashedAdvKey       = "Hashed adv key"
    private static let fieldMAC                = "MAC"
    private static let fieldPayload            = "Payload"

    // MARK: - Optional field names

    private static let fieldPrivateKeyHex      = "Private key (Hex)"
    private static let fieldAdvertisementKey   = "Advertisement key"
    private static let fieldAdvertisementKeyHex = "Advertisement key (Hex)"

    // MARK: - Public API

    /// Parse a `.keys` file from disk.
    ///
    /// - Parameter url: URL of the `.keys` file on disk.
    /// - Returns: A `KeysParseResult`; `privateKeyBase64` is ephemeral.
    /// - Throws: `KeysParseError.fileNotReadable` if the file cannot be opened,
    ///           `KeysParseError.invalidEncoding` if the content is not valid UTF-8.
    func parse(url: URL) throws -> KeysParseResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw KeysParseError.fileNotReadable
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw KeysParseError.invalidEncoding
        }

        let fileName = url.lastPathComponent
        return parseContent(content, sourceFileName: fileName)
    }

    /// Parse raw `.keys` file content directly (without reading from disk).
    ///
    /// - Parameters:
    ///   - content: The full text content of the `.keys` file.
    ///   - sourceFileName: The original file name (used to derive `displayName`).
    /// - Returns: A `KeysParseResult`; `privateKeyBase64` is ephemeral.
    func parseContent(_ content: String, sourceFileName: String = "unknown.keys") -> KeysParseResult {
        // Build a case-insensitive lookup dictionary from the file lines.
        var fields: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            // Split only on the first colon.
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let rawKey   = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !rawKey.isEmpty else { continue }
            // Store with lowercased key for case-insensitive lookup.
            fields[rawKey.lowercased()] = rawValue
        }

        // Helper: look up a field by canonical name (case-insensitive).
        func value(for canonical: String, aliases: [String] = []) -> String? {
            ([canonical] + aliases)
                .lazy
                .compactMap { fields[$0.lowercased()] }
                .first { !$0.isEmpty }
        }

        // Collect required fields and validation errors.
        var validationErrors: [KeysValidationError] = []

        func require(_ fieldName: String, aliases: [String] = []) -> String {
            let v = value(for: fieldName, aliases: aliases) ?? ""
            if v.isEmpty {
                validationErrors.append(
                    KeysValidationError(
                        field: fieldName,
                        message: "Required field '\(fieldName)' is missing or empty."
                    )
                )
            }
            return v
        }

        let privateKeyBase64     = require(Self.fieldPrivateKey, aliases: ["Private key (Base64)"])
        let hashedAdvKeyBase64   = require(Self.fieldHashedAdvKey, aliases: ["Hashed adv key (Base64)"])
        let generatedFindMyMac   = require(Self.fieldMAC)
        let payload              = require(Self.fieldPayload)

        // Optional fields (no validation error if absent).
        let advertisementKeyBase64 = value(for: Self.fieldAdvertisementKey, aliases: ["Advertisement key (Base64)"]).flatMap { $0.isEmpty ? nil : $0 }
        let advertisementKeyHex    = value(for: Self.fieldAdvertisementKeyHex).flatMap { $0.isEmpty ? nil : $0 }
        // Private key (Hex) is secret material — not stored in the record.

        // Derive displayName from sourceFileName (without extension), defaulting to "Flipper Zero".
        let nameWithoutExtension = (sourceFileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (nameWithoutExtension.isEmpty || nameWithoutExtension == ".keys")
            ? "Flipper Zero"
            : nameWithoutExtension

        let record = FindMyKeyRecord(
            id: UUID(),
            displayName: displayName,
            sourceFileName: sourceFileName,
            importedAt: Date(),
            advertisementKeyBase64: advertisementKeyBase64,
            advertisementKeyHex: advertisementKeyHex,
            hashedAdvKeyBase64: hashedAdvKeyBase64,
            generatedFindMyMac: generatedFindMyMac,
            payload: payload,
            keychainKeyID: UUID()
        )

        return KeysParseResult(
            record: record,
            privateKeyBase64: privateKeyBase64,
            validationErrors: validationErrors
        )
    }
}
