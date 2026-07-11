import Foundation
import Security

struct KeychainService {
    static let defaultService = "com.findmyflipper.mac.private-keys"

    private let service: String
    private let legacyServices: [String]

    init(service: String = Self.defaultService, legacyServices: [String]? = nil) {
        self.service = service
        if let legacyServices {
            self.legacyServices = legacyServices
        } else if service == Self.defaultService {
            self.legacyServices = [
                Bundle.main.bundleIdentifier,
                "com.arxhsz.FindMyFlipperMac",
                "com.findmyflipper.mac"
            ]
            .compactMap { $0 }
            .filter { $0 != service }
        } else {
            self.legacyServices = []
        }
    }

    // MARK: - Save

    func savePrivateKey(_ base64Key: String, forID keyID: UUID) throws {
        guard let data = base64Key.data(using: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecParam)
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: keyID.uuidString,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
            kSecValueData: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            throw KeychainError.duplicateItem
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Load

    func loadPrivateKey(forID keyID: UUID) throws -> String {
        do {
            return try loadPrivateKey(forID: keyID, service: service)
        } catch KeychainError.itemNotFound {
            return try migrateLegacyPrivateKey(forID: keyID)
        }
    }

    private func loadPrivateKey(forID keyID: UUID, service: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: keyID.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound || result == nil {
            throw KeychainError.itemNotFound
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let keyString = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecDecode)
        }

        return keyString
    }

    private func migrateLegacyPrivateKey(forID keyID: UUID) throws -> String {
        for legacyService in legacyServices {
            guard let value = try? loadPrivateKey(forID: keyID, service: legacyService) else {
                continue
            }

            do {
                try savePrivateKey(value, forID: keyID)
            } catch KeychainError.duplicateItem {
                // Another caller completed the migration first.
            }
            deletePrivateKey(forID: keyID, service: legacyService)
            return value
        }
        throw KeychainError.itemNotFound
    }

    // MARK: - Delete

    func deletePrivateKey(forID keyID: UUID) throws {
        let status = deletePrivateKey(forID: keyID, service: service)

        if status == errSecItemNotFound {
            throw KeychainError.itemNotFound
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    @discardableResult
    private func deletePrivateKey(forID keyID: UUID, service: String) -> OSStatus {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: keyID.uuidString
        ]

        return SecItemDelete(query as CFDictionary)
    }

    // MARK: - Exists

    func privateKeyExists(forID keyID: UUID) -> Bool {
        return (try? loadPrivateKey(forID: keyID)) != nil
    }
}
