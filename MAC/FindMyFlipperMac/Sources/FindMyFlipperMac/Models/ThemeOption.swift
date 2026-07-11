import Foundation

enum ThemeOption: String, Codable, CaseIterable, Equatable {
    case light
    case dark
    case system
    case sunset
    case ocean
    case forest
    case purple

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .purple: return "Purple"
        }
    }
}
