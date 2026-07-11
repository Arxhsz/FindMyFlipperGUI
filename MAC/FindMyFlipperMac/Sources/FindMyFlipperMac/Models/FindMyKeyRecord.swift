import Foundation

struct FindMyKeyRecord: Identifiable, Codable {
    var id: UUID
    var displayName: String
    var sourceFileName: String
    var importedAt: Date
    // Public/non-secret fields only — private key lives in Keychain
    var advertisementKeyBase64: String?
    var advertisementKeyHex: String?
    var hashedAdvKeyBase64: String
    var generatedFindMyMac: String
    var payload: String
    /// Key used to retrieve private key from Keychain
    var keychainKeyID: UUID
}
