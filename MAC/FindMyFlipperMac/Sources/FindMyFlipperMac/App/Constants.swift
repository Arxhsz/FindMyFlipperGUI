import Foundation

enum Constants {
    /// Base URL for the bundled local Python FastAPI backend
    static let backendBaseURL = "http://127.0.0.1:8765"

    /// Maximum number of location reports stored per profile
    static let maxReportsPerProfile = 10_000

    /// Default automatic refresh interval in minutes
    static let defaultRefreshInterval = 15

    /// App bundle identifier
    static let bundleIdentifier = "com.findmyflipper.mac"

    /// Keychain service name (matches bundle identifier)
    static let keychainService = bundleIdentifier

    /// BLE reconnect poll interval in seconds
    static let bleReconnectPollInterval: TimeInterval = 5

    /// Backend health poll interval during startup
    static let backendHealthPollInterval: TimeInterval = 1

    /// Backend startup timeout in seconds
    static let backendStartupTimeout: TimeInterval = 10

    /// BLE RSSI threshold for "recommended" score
    static let bleRSSIRecommended = -65

    /// BLE RSSI threshold for "weak" score
    static let bleRSSIWeak = -80

    /// BLE RSSI threshold for "possible" score
    static let bleRSSIPossible = -75

    /// BLE device considered recent if seen within this many seconds
    static let bleRecentThreshold: TimeInterval = 60

    /// Battery level threshold for low-battery notification
    static let lowBatteryThreshold = 20

    /// MapKit clustering threshold for historical report annotations
    static let mapClusteringThreshold = 50

    /// Minimum report age in minutes for animated pulse ring on map marker
    static let mapMarkerPulseThreshold: TimeInterval = 10 * 60
}
