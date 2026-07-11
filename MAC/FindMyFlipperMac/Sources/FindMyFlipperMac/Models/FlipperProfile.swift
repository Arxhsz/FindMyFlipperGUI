import Foundation

struct FlipperProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var displayName: String
    var createdAt: Date
    var updatedAt: Date
    /// References FindMyKeyRecord.id
    var findMyKeyID: UUID
    /// References BLEDeviceRecord.id
    var bleDeviceID: UUID?
    /// From .keys MAC field
    var generatedFindMyMac: String
    /// Truncated, non-secret
    var payloadPreview: String
    /// Truncated, non-secret
    var hashedAdvKeyPreview: String
    var lastReport: LocationReport?
    var lastBLEConnection: Date?
    /// 0-100 or nil
    var batteryLevel: Int?
    var isBLEConnected: Bool
    var autoReconnect: Bool
    var refreshInterval: RefreshInterval
    var isActive: Bool
    var bleDeviceName: String? = nil
    var lastBLERSSI: Int? = nil
    var detectedBLEServices: [String]? = nil
    var firmwareVersion: String? = nil
}
