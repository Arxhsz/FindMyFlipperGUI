import Foundation
import Combine

enum ProfileStoreError: LocalizedError {
    case notFound
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notFound: return "Profile or record not found."
        case .encodingFailed: return "Failed to encode data for storage."
        }
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [FlipperProfile] = []

    private let profilesURL: URL
    private let keyRecordsURL: URL
    private var keyRecords: [FindMyKeyRecord] = []

    init(containerURL: URL? = nil) {
        let base = containerURL ?? Self.defaultContainerURL()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        profilesURL = base.appendingPathComponent("profiles.json")
        keyRecordsURL = base.appendingPathComponent("key_records.json")
        load()
    }

    // MARK: - Profile CRUD

    func saveProfile(_ profile: FlipperProfile) throws {
        var p = profile
        p.createdAt = Date()
        p.updatedAt = Date()
        profiles.append(p)
        try persistProfiles()
    }

    func updateProfile(_ profile: FlipperProfile) throws {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.notFound
        }
        var p = profile
        p.updatedAt = Date()
        profiles[idx] = p
        try persistProfiles()
    }

    func deleteProfile(id: UUID) throws {
        guard let deleted = profiles.first(where: { $0.id == id }) else {
            throw ProfileStoreError.notFound
        }
        profiles.removeAll { $0.id == id }
        if deleted.isActive, !profiles.isEmpty, !profiles.contains(where: { $0.isActive }) {
            profiles[0].isActive = true
            profiles[0].updatedAt = Date()
        }
        try persistProfiles()
    }

    func activeProfile() -> FlipperProfile? {
        profiles.first { $0.isActive }
    }

    func setActive(profileID: UUID) throws {
        guard profiles.contains(where: { $0.id == profileID }) else {
            throw ProfileStoreError.notFound
        }
        for idx in profiles.indices {
            profiles[idx].isActive = (profiles[idx].id == profileID)
        }
        try persistProfiles()
    }

    /// Link a newly imported Find My identity to the current profile while
    /// preserving the user's BLE selection and profile preferences.
    @discardableResult
    func relinkActiveProfile(to record: FindMyKeyRecord) throws -> FlipperProfile {
        guard let index = profiles.firstIndex(where: { $0.isActive }) else {
            throw ProfileStoreError.notFound
        }

        profiles[index].findMyKeyID = record.id
        profiles[index].generatedFindMyMac = record.generatedFindMyMac
        profiles[index].payloadPreview = String(record.payload.prefix(64))
        profiles[index].hashedAdvKeyPreview = String(record.hashedAdvKeyBase64.prefix(12))
        profiles[index].updatedAt = Date()
        try persistProfiles()
        return profiles[index]
    }

    // MARK: - Key Records

    func saveKeyRecord(_ record: FindMyKeyRecord) throws {
        keyRecords.append(record)
        try persistKeyRecords()
    }

    func loadKeyRecord(id: UUID) throws -> FindMyKeyRecord {
        guard let record = keyRecords.first(where: { $0.id == id }) else {
            throw ProfileStoreError.notFound
        }
        return record
    }

    var keyRecordsNewestFirst: [FindMyKeyRecord] {
        keyRecords.sorted { $0.importedAt > $1.importedAt }
    }

    func deleteKeyRecord(id: UUID) throws {
        keyRecords.removeAll { $0.id == id }
        try persistKeyRecords()
    }

    /// Removes key metadata that is no longer linked to any profile and
    /// returns the records whose Keychain entries can now be deleted.
    func removeUnreferencedKeyRecords() throws -> [FindMyKeyRecord] {
        let referencedIDs = Set(profiles.map(\.findMyKeyID))
        let removed = keyRecords.filter { !referencedIDs.contains($0.id) }
        keyRecords.removeAll { !referencedIDs.contains($0.id) }
        try persistKeyRecords()
        return removed
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: profilesURL),
           let loaded = try? decoder.decode([FlipperProfile].self, from: data) {
            profiles = loaded
        }
        if let data = try? Data(contentsOf: keyRecordsURL),
           let loaded = try? decoder.decode([FindMyKeyRecord].self, from: data) {
            keyRecords = loaded
        }
    }

    private func persistProfiles() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(profiles)
        try data.write(to: profilesURL, options: .atomic)
    }

    private func persistKeyRecords() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(keyRecords)
        try data.write(to: keyRecordsURL, options: .atomic)
    }

    private static func defaultContainerURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FindMyFlipperMac")
    }
}
