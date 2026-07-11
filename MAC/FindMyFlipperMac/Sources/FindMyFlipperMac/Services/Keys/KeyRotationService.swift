import Foundation

struct KeyRotationResult: Equatable {
    let activeFilename: String
    let removedMacRecords: Int
    let removedFlipperFiles: Int
}

@MainActor
final class KeyRotationService: ObservableObject {
    @Published private(set) var isRotating = false
    @Published private(set) var statusMessage: String?

    private let backendManager: BackendManager
    private let backendClient: BackendClient
    private let keychain: KeychainService
    private let profileStore: ProfileStore

    init(
        backendManager: BackendManager,
        backendClient: BackendClient,
        keychain: KeychainService,
        profileStore: ProfileStore
    ) {
        self.backendManager = backendManager
        self.backendClient = backendClient
        self.keychain = keychain
        self.profileStore = profileStore
    }

    func rotateActiveProfileKeys() async throws -> KeyRotationResult {
        guard profileStore.activeProfile() != nil else { throw KeyRotationError.noActiveProfile }
        guard FlipperSDCardService.isFlipperConnected else { throw FlipperSDCardError.notConnected }

        isRotating = true
        statusMessage = "Generating and validating a new Find My identity..."
        defer { isRotating = false }

        await backendManager.startBackend()
        let response = try await backendClient.generateKeys()
        guard response.ok, let rawContent = response.rawContent, !rawContent.isEmpty else {
            throw KeyRotationError.generationFailed(response.error ?? "The backend returned no key data.")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "findmyflipper-\(formatter.string(from: Date())).keys"
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindMyFlipperRotation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let tempFile = tempDirectory.appendingPathComponent(filename)
        try rawContent.write(to: tempFile, atomically: true, encoding: .utf8)

        let importer = KeyImportService(keychain: keychain, profileStore: profileStore)
        let record = try await importer.importKeysFile(
            url: tempFile,
            displayName: profileStore.activeProfile()?.displayName
        )

        do {
            statusMessage = "Copying the new identity to the connected Flipper..."
            _ = try await FlipperSDCardService.writeKeysToFlipperSD(rawContent: rawContent, filename: filename)
            let filesAfterWrite = try await FlipperSDCardService.listKeysFiles()
            guard filesAfterWrite.contains(where: { $0.caseInsensitiveCompare(filename) == .orderedSame }) else {
                throw KeyRotationError.verificationFailed(
                    "The Flipper did not list the new file after transfer. Found: \(filesAfterWrite.joined(separator: ", "))"
                )
            }
            try profileStore.relinkActiveProfile(to: record)
        } catch {
            try? profileStore.deleteKeyRecord(id: record.id)
            try? keychain.deletePrivateKey(forID: record.keychainKeyID)
            throw error
        }

        statusMessage = "Removing older key bundles..."
        let deletedFlipperFiles = try await FlipperSDCardService.deleteKeysFiles(except: filename)
        let finalFlipperFiles = try await FlipperSDCardService.listKeysFiles()
        guard finalFlipperFiles.count == 1,
              finalFlipperFiles[0].caseInsensitiveCompare(filename) == .orderedSame else {
            throw KeyRotationError.verificationFailed(
                "Cleanup was not confirmed. The Flipper currently lists: \(finalFlipperFiles.joined(separator: ", "))"
            )
        }
        let removedRecords = try profileStore.removeUnreferencedKeyRecords()
        for oldRecord in removedRecords {
            do {
                try keychain.deletePrivateKey(forID: oldRecord.keychainKeyID)
            } catch KeychainError.itemNotFound {
                continue
            }
        }

        let result = KeyRotationResult(
            activeFilename: filename,
            removedMacRecords: removedRecords.count,
            removedFlipperFiles: deletedFlipperFiles.count
        )
        statusMessage = "New keys active: \(filename). Removed \(removedRecords.count) old Mac record(s) and \(deletedFlipperFiles.count) old Flipper file(s)."
        return result
    }
}

enum KeyRotationError: LocalizedError {
    case noActiveProfile
    case generationFailed(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveProfile:
            return "No active Flipper profile is available to relink."
        case .generationFailed(let detail):
            return "Could not generate replacement keys. \(detail)"
        case .verificationFailed(let detail):
            return "Could not verify the Flipper key folder. \(detail)"
        }
    }
}
