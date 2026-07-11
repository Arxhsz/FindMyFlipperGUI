import Foundation

struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool = false
    var startInMenuBar: Bool = false
    var minimizeToMenuBar: Bool = false
    var refreshInterval: RefreshInterval = .fifteenMin
    var theme: ThemeOption = .light
    var accentColor: String = "#FF5A00"
    var mapDisplayMode: MapDisplayMode = .standard
    var flipperIconStyle: FlipperIconStyle = .white
    var distanceUnit: DistanceUnit = .metric
    var notifyOnNewReport: Bool = true
    var notifyFlipperNearby: Bool = true
    var notifyLowBattery: Bool = true
    var debugLogsEnabled: Bool = false
    var backendPort: Int = 8765

    enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case startInMenuBar
        case minimizeToMenuBar
        case refreshInterval
        case theme
        case accentColor
        case mapDisplayMode
        case flipperIconStyle
        case distanceUnit
        case notifyOnNewReport
        case notifyFlipperNearby
        case notifyLowBattery
        case debugLogsEnabled
        case backendPort
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        startInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .startInMenuBar) ?? false
        minimizeToMenuBar = try container.decodeIfPresent(Bool.self, forKey: .minimizeToMenuBar) ?? false
        refreshInterval = try container.decodeIfPresent(RefreshInterval.self, forKey: .refreshInterval) ?? .fifteenMin
        theme = try container.decodeIfPresent(ThemeOption.self, forKey: .theme) ?? .light
        accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor) ?? "#FF5A00"
        mapDisplayMode = try container.decodeIfPresent(MapDisplayMode.self, forKey: .mapDisplayMode) ?? .standard
        flipperIconStyle = try container.decodeIfPresent(FlipperIconStyle.self, forKey: .flipperIconStyle) ?? .white
        distanceUnit = try container.decodeIfPresent(DistanceUnit.self, forKey: .distanceUnit) ?? .metric
        notifyOnNewReport = try container.decodeIfPresent(Bool.self, forKey: .notifyOnNewReport) ?? true
        notifyFlipperNearby = try container.decodeIfPresent(Bool.self, forKey: .notifyFlipperNearby) ?? true
        notifyLowBattery = try container.decodeIfPresent(Bool.self, forKey: .notifyLowBattery) ?? true
        debugLogsEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugLogsEnabled) ?? false
        backendPort = try container.decodeIfPresent(Int.self, forKey: .backendPort) ?? 8765
    }
}

enum RefreshInterval: Int, Codable, CaseIterable, Equatable {
    case manual = 0
    case fiveMin = 5
    case fifteenMin = 15
    case thirtyMin = 30

    var displayName: String {
        switch self {
        case .manual: return "Manual only"
        case .fiveMin: return "5 minutes"
        case .fifteenMin: return "15 minutes"
        case .thirtyMin: return "30 minutes"
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Equatable {
    case metric
    case imperial
}

enum MapDisplayMode: String, Codable, CaseIterable, Equatable {
    case standard
    case hybrid
    case imagery

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .hybrid: return "Hybrid"
        case .imagery: return "Satellite"
        }
    }

    var next: MapDisplayMode {
        switch self {
        case .standard: return .hybrid
        case .hybrid: return .imagery
        case .imagery: return .standard
        }
    }
}

enum FlipperIconStyle: String, Codable, CaseIterable, Equatable {
    case white
    case black
    case transparent

    var displayName: String {
        switch self {
        case .white: return "Flipper Zero"
        case .black: return "Black"
        case .transparent: return "Transparent"
        }
    }

    var selectionColorHex: String {
        switch self {
        case .white: return "#FF5A00"
        case .black: return "#6B7280"
        case .transparent: return "#2DD4BF"
        }
    }
}
