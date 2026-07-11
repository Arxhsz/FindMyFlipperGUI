import SwiftUI

// MARK: - ThemeColors

struct ThemeColors {
    var primaryOrange: Color
    var deepOrange: Color
    var softOrangeSurface: Color
    var background: Color
    var sidebarBackground: Color
    var cardBackground: Color
    var cardBorder: Color
    var textPrimary: Color
    var textSecondary: Color
    var successGreen: Color
    var warningAmber: Color
    var errorRed: Color

    // MARK: - Seven static theme instances

    static let light = ThemeColors(
        primaryOrange: Color(hex: "#FF5A00"),
        deepOrange: Color(hex: "#E84D00"),
        softOrangeSurface: Color(hex: "#FFF1E8"),
        background: Color(hex: "#F7F7F5"),
        sidebarBackground: Color(hex: "#FFFFFF"),
        cardBackground: Color(hex: "#FFFFFF"),
        cardBorder: Color(hex: "#E9E5DF"),
        textPrimary: Color(hex: "#1F2328"),
        textSecondary: Color(hex: "#6B7280"),
        successGreen: Color(hex: "#22C55E"),
        warningAmber: Color(hex: "#F59E0B"),
        errorRed: Color(hex: "#EF4444")
    )

    static let dark = ThemeColors(
        primaryOrange: Color(hex: "#FF6A1A"),
        deepOrange: Color(hex: "#E84D00"),
        softOrangeSurface: Color(hex: "#2A1A10"),
        background: Color(hex: "#0F1115"),
        sidebarBackground: Color(hex: "#14171D"),
        cardBackground: Color(hex: "#1B1F27"),
        cardBorder: Color(hex: "#2A2F3A"),
        textPrimary: Color(hex: "#F9FAFB"),
        textSecondary: Color(hex: "#A1A1AA"),
        successGreen: Color(hex: "#22C55E"),
        warningAmber: Color(hex: "#F59E0B"),
        errorRed: Color(hex: "#EF4444")
    )

    static let sunset = ThemeColors(
        primaryOrange: Color(hex: "#F97316"),
        deepOrange: Color(hex: "#EA580C"),
        softOrangeSurface: Color(hex: "#2D1B0E"),
        background: Color(hex: "#1A0E0A"),
        sidebarBackground: Color(hex: "#231208"),
        cardBackground: Color(hex: "#2D1B0E"),
        cardBorder: Color(hex: "#6B2D1A"),
        textPrimary: Color(hex: "#FEF3C7"),
        textSecondary: Color(hex: "#D97706"),
        successGreen: Color(hex: "#4ADE80"),
        warningAmber: Color(hex: "#FBBF24"),
        errorRed: Color(hex: "#F87171")
    )

    static let ocean = ThemeColors(
        primaryOrange: Color(hex: "#0EA5E9"),
        deepOrange: Color(hex: "#0284C7"),
        softOrangeSurface: Color(hex: "#0C1F2F"),
        background: Color(hex: "#070F18"),
        sidebarBackground: Color(hex: "#0B1825"),
        cardBackground: Color(hex: "#0F2133"),
        cardBorder: Color(hex: "#164E63"),
        textPrimary: Color(hex: "#E0F2FE"),
        textSecondary: Color(hex: "#7DD3FC"),
        successGreen: Color(hex: "#34D399"),
        warningAmber: Color(hex: "#FBBF24"),
        errorRed: Color(hex: "#F87171")
    )

    static let forest = ThemeColors(
        primaryOrange: Color(hex: "#22C55E"),
        deepOrange: Color(hex: "#16A34A"),
        softOrangeSurface: Color(hex: "#0D1F11"),
        background: Color(hex: "#081008"),
        sidebarBackground: Color(hex: "#0C160C"),
        cardBackground: Color(hex: "#111E11"),
        cardBorder: Color(hex: "#1B3A1B"),
        textPrimary: Color(hex: "#DCFCE7"),
        textSecondary: Color(hex: "#86EFAC"),
        successGreen: Color(hex: "#4ADE80"),
        warningAmber: Color(hex: "#FBBF24"),
        errorRed: Color(hex: "#F87171")
    )

    static let purple = ThemeColors(
        primaryOrange: Color(hex: "#A855F7"),
        deepOrange: Color(hex: "#9333EA"),
        softOrangeSurface: Color(hex: "#1B0D2A"),
        background: Color(hex: "#0D0814"),
        sidebarBackground: Color(hex: "#140B1E"),
        cardBackground: Color(hex: "#1B0D2A"),
        cardBorder: Color(hex: "#3B1F5E"),
        textPrimary: Color(hex: "#F5F3FF"),
        textSecondary: Color(hex: "#C4B5FD"),
        successGreen: Color(hex: "#34D399"),
        warningAmber: Color(hex: "#FBBF24"),
        errorRed: Color(hex: "#F87171")
    )

    /// Returns the ThemeColors for a given ThemeOption, respecting system appearance for .system.
    static func colors(for option: ThemeOption, colorScheme: ColorScheme = .light) -> ThemeColors {
        switch option {
        case .light:   return .light
        case .dark:    return .dark
        case .system:  return colorScheme == .dark ? .dark : .light
        case .sunset:  return .sunset
        case .ocean:   return .ocean
        case .forest:  return .forest
        case .purple:  return .purple
        }
    }
}

// MARK: - EnvironmentKey

struct AppThemeKey: EnvironmentKey {
    static let defaultValue: ThemeColors = .light
}

extension EnvironmentValues {
    var appTheme: ThemeColors {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Color hex initializer helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
