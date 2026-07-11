import Foundation

struct BLEDeviceRecord: Identifiable, Codable, Equatable {
    var id: UUID
    /// CoreBluetooth CB identifier
    var peripheralIdentifier: UUID
    var lastKnownName: String?
    var discoveredName: String?
    var lastRSSI: Int
    var detectedServiceUUIDs: [String]
    var manufacturerData: Data?
    var lastSeenBLE: Date
    var selectedByUser: Bool
    var autoReconnectEnabled: Bool
    var score: BLEDeviceScore

    var displayName: String {
        lastKnownName ?? discoveredName ?? "Unknown Device"
    }
}

enum BLEDeviceScore: String, Codable, CaseIterable, Equatable {
    /// Flipper/FZ name + strong RSSI + recent
    case recommended
    /// Partial name match or moderate RSSI
    case possibleFlipper
    case unknown
    /// Poor RSSI or old timestamp
    case weak
}
