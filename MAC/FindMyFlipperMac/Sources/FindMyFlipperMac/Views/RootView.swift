import SwiftUI

// MARK: - RootView

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors {
        ThemeColors.colors(for: appState.settings.theme, colorScheme: colorScheme)
    }

    var body: some View {
        Group {
            if appState.onboardingComplete {
                MainAppView()
            } else {
                OnboardingContainerView()
            }
        }
        .environment(\.appTheme, theme)
        .tint(theme.primaryOrange)
        .onAppear {
            let backendManager = appState.backendManager
            Task.detached(priority: .utility) {
                await backendManager.startBackend()
            }
            if appState.activeProfile != nil {
                appState.refreshService.startAutomaticRefresh()
                appState.bleManager.resumeAutoReconnect()
            }
        }
        .onChange(of: appState.activeProfile?.id) { _, newID in
            if newID != nil {
                appState.refreshService.startAutomaticRefresh()
            } else {
                appState.refreshService.stopAutomaticRefresh()
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .background(theme.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .windowToolbar)
    }
}

// MARK: - MainAppView

struct MainAppView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 220)
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background.ignoresSafeArea())
                .ignoresSafeArea(.container, edges: .top)
        }
        .background(theme.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private var contentView: some View {
        switch router.currentDestination {
        case .map:          MainMapView()
        case .dashboard:    DashboardView()
        case .reports:      ReportsView()
        case .flipperDetail: FlipperDetailView()
        case .profiles:     ProfilesView()
        case .settings:     SettingsView()
        case .onboarding:   OnboardingContainerView()
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    private struct NavItem: Identifiable {
        let id: AppDestination
        let label: String
        let icon: String
    }

    private let navItems: [NavItem] = [
        NavItem(id: .map,          label: "Map",      icon: "map.fill"),
        NavItem(id: .dashboard,    label: "Dashboard", icon: "square.grid.2x2.fill"),
        NavItem(id: .reports,      label: "Reports",   icon: "doc.text.fill"),
        NavItem(id: .flipperDetail, label: "Flipper",   icon: "flipper.glyph"),
        NavItem(id: .profiles,     label: "Profiles",  icon: "person.2.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // App brand header
            HStack(spacing: 12) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.primaryOrange)
                Text("FindMyFlipper")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 28) // Space for window controls
            .padding(.bottom, 14)

            Divider()

            // Navigation items
            VStack(spacing: 2) {
                ForEach(navItems) { item in
                    SidebarRow(
                        label: item.label,
                        icon: item.icon,
                        isActive: router.currentDestination == item.id
                    ) {
                        router.currentDestination = item.id
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)

            Spacer()

            Divider()

            // Bottom: Flipper Status + Settings
            VStack(spacing: 16) {
                // Flipper Status Widget
                if let profile = appState.activeProfile {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(profile.isBLEConnected ? theme.successGreen : theme.textSecondary)
                                .frame(width: 8, height: 8)
                            Text(profile.isBLEConnected ? "Flipper Connected" : "Flipper Disconnected")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }

                        if let battery = profile.batteryLevel {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Battery").font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1)
                                    Text("\(battery)%").font(.caption).fontWeight(.medium).foregroundStyle(theme.textPrimary).lineLimit(1)
                                }
                                Spacer()
                                BatteryPill(level: battery)
                            }
                        }

                        if let lastReport = appState.reportsStore.latestReport(forProfile: profile.id) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Last Update").font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1)
                                    Text(relativeTime(lastReport.timestamp)).font(.caption).fontWeight(.medium).foregroundStyle(theme.textPrimary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "clock")
                                    .font(.caption)
                                    .foregroundStyle(theme.primaryOrange)
                            }
                        }
                    }
                    .padding(12)
                    .frame(minHeight: 112)
                    .background(theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Settings
                SidebarRow(
                    label: "Settings",
                    icon: "gearshape",
                    isActive: router.currentDestination == .settings
                ) {
                    router.currentDestination = .settings
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .background(theme.sidebarBackground)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 220)
    }

    private func relativeTime(_ ts: TimeInterval) -> String {
        let age = Date().timeIntervalSince1970 - ts
        if age < 60 { return "Just now" }
        if age < 3600 { return "\(Int(age/60)) min ago" }
        if age < 86400 { return "\(Int(age/3600)) hrs ago" }
        return "\(Int(age/86400)) days ago"
    }
}

// MARK: - SidebarRow

private struct SidebarRow: View {
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Group {
                    if icon == "flipper.glyph" {
                        FlipperGlyphIcon()
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                    }
                }
                .foregroundStyle(isActive ? theme.primaryOrange : theme.textSecondary)
                .frame(width: 20, height: 20)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? theme.softOrangeSurface : (isHovered ? theme.cardBorder.opacity(0.4) : Color.clear))
            )
            .animation(.easeInOut(duration: 0.12), value: isActive)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
        .environmentObject(AppRouter())
}
