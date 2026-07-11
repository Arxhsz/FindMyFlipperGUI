import SwiftUI
import AppKit

enum FlipperProductImageLoader {
    private static var cachedImage: NSImage?
    private static var loadTask: Task<NSImage?, Never>?

    static func load() async -> NSImage? {
        if let cachedImage { return cachedImage }
        if let loadTask { return await loadTask.value }

        let task = Task.detached(priority: .utility) {
            guard let resources = Bundle.main.resourceURL else { return nil as NSImage? }
            let packagedURL = resources.appendingPathComponent("flipper-zero.png")
            guard FileManager.default.fileExists(atPath: packagedURL.path) else { return nil }
            return NSImage(contentsOf: packagedURL)
        }
        loadTask = task
        let image = await task.value
        cachedImage = image
        loadTask = nil
        return image
    }
}

// MARK: - PrimaryButton

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isPressed = false

    init(_ title: String, icon: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPressed ? theme.deepOrange : theme.primaryOrange)
                    .shadow(color: theme.primaryOrange.opacity(0.35), radius: 6, y: 2)
            )
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .onDisappear { isPressed = false }
    }
}

// MARK: - SecondaryButton

struct SecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.medium)
            }
            .foregroundStyle(theme.primaryOrange)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.primaryOrange, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StatusBadge

struct StatusBadge: View {
    let label: String
    let color: Color
    let icon: String?

    init(_ label: String, color: Color, icon: String? = nil) {
        self.label = label
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.6), radius: 3)
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - BatteryPill

enum BatteryDisplay {
    static func color(for level: Int?, theme: ThemeColors) -> Color {
        guard let level else { return theme.textSecondary }
        let clamped = max(0, min(100, level))

        if clamped >= 70 { return theme.successGreen }
        if clamped >= 60 {
            return interpolate(from: (245, 158, 11), to: (34, 197, 94), progress: Double(clamped - 60) / 10)
        }
        if clamped >= 30 {
            return interpolate(from: (255, 90, 0), to: (245, 158, 11), progress: Double(clamped - 30) / 30)
        }
        if clamped > 10 {
            return interpolate(from: (239, 68, 68), to: (255, 90, 0), progress: Double(clamped - 10) / 20)
        }
        return theme.errorRed
    }

    static func symbolName(for level: Int?) -> String {
        guard let level else { return "battery.0" }
        if level >= 75 { return "battery.100" }
        if level >= 50 { return "battery.75" }
        if level >= 25 { return "battery.50" }
        if level >= 10 { return "battery.25" }
        return "battery.0"
    }

    static func percentSymbolName(for level: Int?) -> String {
        guard let level else { return "battery.0percent" }
        if level >= 75 { return "battery.100percent" }
        if level >= 50 { return "battery.75percent" }
        if level >= 25 { return "battery.50percent" }
        if level >= 10 { return "battery.25percent" }
        return "battery.0percent"
    }

    private static func interpolate(
        from start: (Double, Double, Double),
        to end: (Double, Double, Double),
        progress: Double
    ) -> Color {
        let t = max(0, min(1, progress))
        let red = (start.0 + (end.0 - start.0) * t) / 255
        let green = (start.1 + (end.1 - start.1) * t) / 255
        let blue = (start.2 + (end.2 - start.2) * t) / 255
        return Color(.sRGB, red: red, green: green, blue: blue)
    }
}

struct BatteryPill: View {
    let level: Int?

    @Environment(\.appTheme) private var theme

    private var batteryColor: Color {
        BatteryDisplay.color(for: level, theme: theme)
    }

    private var batteryIcon: String {
        BatteryDisplay.symbolName(for: level)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon)
                .font(.caption)
                .foregroundStyle(batteryColor)
            Text(level.map { "\($0)%" } ?? "—")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(batteryColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(batteryColor.opacity(0.12), in: Capsule())
    }
}

// MARK: - GlassCard

struct GlassCard<Content: View>: View {
    let content: Content
    @Environment(\.appTheme) private var theme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.cardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?

    @Environment(\.appTheme) private var theme

    init(icon: String, title: String, subtitle: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(theme.softOrangeSurface)
                    .frame(width: 80, height: 80)
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(theme.primaryOrange)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                PrimaryButton(actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: 360)
    }
}

// MARK: - FlipperMarkerView

struct FlipperMarkerView: View {
    let isPulsing: Bool
    var iconStyle: FlipperIconStyle = .white
    var alertToken: Int = 0
    @Environment(\.appTheme) private var theme
    @State private var pulseScale: CGFloat = 1
    @State private var alertScale: CGFloat = 1
    @State private var alertRotation: Double = 0

    var body: some View {
        ZStack {
            if isPulsing {
                Circle()
                    .fill(theme.primaryOrange.opacity(0.25))
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulseScale)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseScale)
                    .onAppear { pulseScale = 1.4 }
            }
            ZStack {
                Circle()
                    .fill(theme.primaryOrange)
                    .frame(width: 40, height: 40)
                    .shadow(color: theme.primaryOrange.opacity(0.5), radius: 7)
                FlipperMiniDevice(style: iconStyle)
                    .frame(width: 32, height: 19)
            }
            .scaleEffect(alertScale)
            .rotationEffect(.degrees(alertRotation))
        }
        .onChange(of: alertToken) { _, _ in
            guard alertToken != 0 else { return }
            Task { @MainActor in
                withAnimation(.spring(response: 0.14, dampingFraction: 0.36)) {
                    alertScale = 1.22
                    alertRotation = -7
                }
                try? await Task.sleep(nanoseconds: 130_000_000)
                withAnimation(.spring(response: 0.16, dampingFraction: 0.44)) {
                    alertRotation = 7
                }
                try? await Task.sleep(nanoseconds: 130_000_000)
                withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) {
                    alertScale = 1
                    alertRotation = 0
                }
            }
        }
    }
}

struct FlipperBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height * 0.16, rect.width * 0.07)
        let leftChamfer = rect.width * 0.24
        let rightChamfer = rect.width * 0.08
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leftChamfer, y: rect.minY + rect.height * 0.03))
        path.addLine(to: CGPoint(x: rect.maxX - rightChamfer - radius, y: rect.minY + rect.height * 0.03))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rightChamfer, y: rect.minY + radius + rect.height * 0.03),
            control: CGPoint(x: rect.maxX - rightChamfer, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - rightChamfer, y: rect.maxY - radius - rect.height * 0.03))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rightChamfer - radius, y: rect.maxY - rect.height * 0.03),
            control: CGPoint(x: rect.maxX - rightChamfer, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + leftChamfer * 0.62, y: rect.maxY - rect.height * 0.03))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + leftChamfer * 0.62, y: rect.minY + rect.height * 0.03))
        path.closeSubpath()
        return path
    }
}

struct FlipperGlyphIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                FlipperBodyShape()
                    .stroke(lineWidth: max(1.7, height * 0.1))
                RoundedRectangle(cornerRadius: height * 0.05, style: .continuous)
                    .stroke(lineWidth: max(1.1, height * 0.07))
                    .frame(width: width * 0.30, height: height * 0.30)
                    .offset(x: -width * 0.10)
                Circle()
                    .fill(.foreground)
                    .frame(width: height * 0.16, height: height * 0.16)
                    .offset(x: width * 0.22)

            }
        }
        .aspectRatio(1.75, contentMode: .fit)
        .accessibilityLabel("Flipper Zero")
    }
}

struct FlipperMiniDevice: View {
    let style: FlipperIconStyle

    private var bodyColor: Color {
        switch style {
        case .white: return Color.white
        case .black: return Color(red: 0.12, green: 0.12, blue: 0.13)
        case .transparent: return Color(red: 0.78, green: 0.9, blue: 0.88).opacity(0.72)
        }
    }

    private var strokeColor: Color {
        switch style {
        case .white: return Color(red: 0.78, green: 0.78, blue: 0.76)
        case .black: return Color(red: 0.34, green: 0.34, blue: 0.36)
        case .transparent: return Color(red: 0.22, green: 0.58, blue: 0.55)
        }
    }

    private var screenColor: Color {
        switch style {
        case .white: return Color(red: 1.0, green: 0.55, blue: 0.06)
        case .black: return Color(red: 1.0, green: 0.48, blue: 0.0)
        case .transparent: return Color(red: 1.0, green: 0.6, blue: 0.12).opacity(0.86)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .center) {
                FlipperBodyShape()
                    .fill(bodyColor)
                    .overlay(
                        FlipperBodyShape()
                            .stroke(strokeColor, lineWidth: max(1, height * 0.06))
                    )
                RoundedRectangle(cornerRadius: height * 0.08, style: .continuous)
                    .fill(screenColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: height * 0.08, style: .continuous)
                            .stroke(Color.black.opacity(0.3), lineWidth: max(0.7, height * 0.04))
                    )
                    .frame(width: width * 0.34, height: height * 0.44)
                    .offset(x: -width * 0.12)
                Circle()
                    .fill(Color(red: 1.0, green: 0.47, blue: 0.0))
                    .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: max(0.6, height * 0.03)))
                    .frame(width: height * 0.38, height: height * 0.38)
                    .offset(x: width * 0.21)

            }
        }
        .aspectRatio(1.75, contentMode: .fit)
    }
}

// MARK: - ThemePreviewTile

struct ThemePreviewTile: View {
    let option: ThemeOption
    let isSelected: Bool
    let onSelect: () -> Void

    private var previewColors: ThemeColors { ThemeColors.colors(for: option) }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(previewColors.background)
                    .frame(width: 64, height: 44)
                    .overlay(
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(previewColors.primaryOrange)
                                .frame(width: 40, height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(previewColors.cardBackground)
                                .frame(width: 40, height: 10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(previewColors.cardBorder, lineWidth: 0.5)
                                )
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? previewColors.primaryOrange : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 4)
                Text(option.displayName)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? previewColors.primaryOrange : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PastLocationMarker

struct PastLocationMarker: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.primaryOrange.opacity(0.18))
                .frame(width: 36, height: 36)
            Circle()
                .fill(theme.primaryOrange)
                .frame(width: 22, height: 22)
                .shadow(color: theme.primaryOrange.opacity(0.4), radius: 4)
            Image(systemName: "mappin")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - RSSIBars

struct RSSIBars: View {
    let rssi: Int
    @Environment(\.appTheme) private var theme

    private var bars: Int {
        if rssi >= -60 { return 4 }
        if rssi >= -70 { return 3 }
        if rssi >= -80 { return 2 }
        return 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i <= bars ? theme.primaryOrange : theme.cardBorder)
                    .frame(width: 4, height: CGFloat(i) * 4 + 2)
            }
        }
    }
}
