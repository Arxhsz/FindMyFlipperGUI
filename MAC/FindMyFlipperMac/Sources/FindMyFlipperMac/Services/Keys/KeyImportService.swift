import Foundation

/// Orchestrates: parse → Keychain save → ProfileStore.saveKeyRecord(_:)
/// Rolls back the Keychain entry if ProfileStore save fails.
@MainActor
final class KeyImportService {
    private let parser: KeysFileParser
    private let keychain: KeychainService
    private let profileStore: ProfileStore

    init(parser: KeysFileParser = KeysFileParser(),
         keychain: KeychainService = KeychainService(),
         profileStore: ProfileStore) {
        self.parser = parser
        self.keychain = keychain
        self.profileStore = profileStore
    }

    /// Import a .keys file: parse → save private key to Keychain → persist record.
    /// Returns the saved FindMyKeyRecord.
    /// Throws if parse fails or any step in the chain fails (with Keychain rollback).
    func importKeysFile(url: URL, displayName: String? = nil) async throws -> FindMyKeyRecord {
        // 1. Parse
        let result = try parser.parse(url: url)
        guard result.isValid else {
            throw KeysParseError.missingRequiredField(result.validationErrors.first?.field ?? "unknown")
        }

        var record = result.record
        if let name = displayName, !name.isEmpty {
            record.displayName = name
        }

        // 2. Save private key to Keychain (FIRST, before any disk write)
        try keychain.savePrivateKey(result.privateKeyBase64, forID: record.keychainKeyID)

        // 3. Persist the record (no private key) — rollback Keychain if this fails
        do {
            try profileStore.saveKeyRecord(record)
        } catch {
            // Rollback: remove just-saved Keychain entry
            try? keychain.deletePrivateKey(forID: record.keychainKeyID)
            throw error
        }

        return record
    }
}
