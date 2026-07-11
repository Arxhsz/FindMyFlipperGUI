import SwiftUI
import MapKit

// MARK: - DashboardView

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.appTheme) private var theme
    @State private var showDiagnostics = false
    @State private var showAppleAccess = false

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.activeProfile?.displayName ?? "No Profile")
                            .font(.title2).fontWeight(.bold).foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("Dashboard").font(.subheadline).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    if appState.refreshService.isRefreshing {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small).tint(theme.primaryOrange)
                            Text("Refreshing…").font(.caption).foregroundStyle(theme.textSecondary)
                        }
                    }
                }

                // Status cards row
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 12
                ) {
                    statusCard(
                        icon: "mappin.and.ellipse",
                        title: "Last Seen",
                        value: lastSeenText,
                        color: theme.primaryOrange
                    )
                    statusCard(
                        icon: BatteryDisplay.symbolName(for: appState.activeProfile?.batteryLevel),
                        title: "Battery",
                        value: appState.activeProfile?.batteryLevel.map { "\($0)%" } ?? "—",
                        color: batteryColor
                    )
                    statusCard(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Bluetooth",
                        value: appState.activeProfile?.isBLEConnected == true ? "Connected" : "Disconnected",
                        color: appState.activeProfile?.isBLEConnected == true ? theme.successGreen : theme.textSecondary
                    )
                    statusCard(
                        icon: "doc.text",
                        title: "Reports",
                        value: "\(appState.reports.count)",
                        color: theme.primaryOrange
                    )
                }
                .frame(height: cardRowHeight(for: proxy.size.width))

                // Map preview card
                if let latestReport = appState.reports.first {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Last Known Location", systemImage: "map.fill")
                                .font(.headline).foregroundStyle(theme.textPrimary)
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: latestReport.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            ))) {
                                Annotation(appState.activeProfile?.displayName ?? "Flipper", coordinate: latestReport.coordinate) {
                                    FlipperMarkerView(
                                        isPulsing: true,
                                        iconStyle: appState.settings.flipperIconStyle,
                                        alertToken: appState.bleManager.alertAnimationToken
                                    )
                                    .id("dashboard-\(appState.settings.flipperIconStyle.rawValue)-\(appState.bleManager.alertAnimationToken)")
                                }
                            }
                            .mapStyle(.standard)
                            .frame(height: mapHeight(for: proxy.size.height))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            HStack {
                                Image(systemName: "location.fill").font(.caption).foregroundStyle(theme.primaryOrange)
                                Text(String(format: "%.5f, %.5f", latestReport.lat, latestReport.lon))
                                    .font(.caption.monospaced()).foregroundStyle(theme.textSecondary)
                                Spacer()
                                Text("\(latestReport.confidence)% confidence")
                                    .font(.caption).foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                } else {
                    GlassCard {
                        EmptyStateView(
                            icon: "map",
                            title: "No Reports Yet",
                            subtitle: "Refresh reports after Apple access is connected."
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: mapHeight(for: proxy.size.height) + 36)
                    }
                }

                // Quick actions
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quick Actions").font(.headline).foregroundStyle(theme.textPrimary)
                        Divider()
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            quickAction(
                                icon: "bell.fill",
                                title: appState.bleManager.alertAvailable ? "Play Alert" : "Alert Unavailable",
                                color: theme.warningAmber,
                                isEnabled: appState.bleManager.alertAvailable
                            ) {
                                appState.bleManager.playAlert()
                            }
                            quickAction(icon: "flipper.glyph", title: "Scan for Flipper", color: theme.primaryOrange) {
                                appState.bleManager.startScan()
                                router.currentDestination = .flipperDetail
                            }
                            quickAction(icon: "checkmark.shield.fill", title: "Test Setup", color: theme.successGreen) {
                                showDiagnostics = true
                            }
                            quickAction(icon: "arrow.triangle.2.circlepath", title: "Refresh Reports", color: .blue) {
                                Task { await appState.refreshService.triggerManualRefresh() }
                            }
                        }
                    }
                }
                .frame(height: proxy.size.width < 900 ? 154 : 174)

                // Refresh error
                if let error = appState.refreshService.refreshError {
                    HStack(spacing: 12) {
                        Image(systemName: error == .authRequired ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.warningAmber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error == .authRequired ? "Reconnect Apple access" : "Report refresh failed")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        if error == .authRequired {
                            Button("Reconnect") { showAppleAccess = true }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.primaryOrange)
                        } else if error == .networkUnavailable || error == .backendNotRunning {
                            Button("Restart Backend") {
                                Task { await appState.backendManager.startBackend() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(theme.warningAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.warningAmber.opacity(0.35)))
                    .frame(height: 62)
                }
            }
            .padding(18)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .background(theme.background)
        .navigationTitle("Dashboard")
        .sheet(isPresented: $showDiagnostics) {
            SetupDiagnosticsPanel(isPresented: $showDiagnostics)
                .environmentObject(appState)
                .environment(\.appTheme, theme)
        }
        .sheet(isPresented: $showAppleAccess) {
            AppleAccessView(
                onContinue: {
                    showAppleAccess = false
                    Task { await appState.refreshService.triggerManualRefresh() }
                },
                onBack: { showAppleAccess = false },
                showsCancelButton: true
            )
            .environmentObject(appState)
            .environment(\.appTheme, theme)
            .frame(width: 520, height: 650)
        }
    }

    private func mapHeight(for availableHeight: CGFloat) -> CGFloat {
        min(max(availableHeight - 380, 112), 210)
    }

    private func cardRowHeight(for availableWidth: CGFloat) -> CGFloat {
        availableWidth < 930 ? 82 : 98
    }

    private var lastSeenText: String {
        guard let report = appState.reports.first else { return "Never" }
        let age = Date().timeIntervalSince1970 - report.timestamp
        if age < 60 { return "Just now" }
        if age < 3600 { return "\(Int(age/60))m ago" }
        return "\(Int(age/3600))h ago"
    }

    private var batteryColor: Color {
        BatteryDisplay.color(for: appState.activeProfile?.batteryLevel, theme: theme)
    }

    private func statusCard(icon: String, title: String, value: String, color: Color) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title3).fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
        .frame(height: 82)
    }

    private func quickAction(
        icon: String,
        title: String,
        color: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    if icon == "flipper.glyph" {
                        FlipperGlyphIcon()
                            .foregroundStyle(color)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: icon).foregroundStyle(color).font(.system(size: 16))
                    }
                }
                Text(title).font(.subheadline).fontWeight(.medium).foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(theme.textSecondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .leading)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

private struct SetupDiagnosticsPanel: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.appTheme) private var theme
    @Binding var isPresented: Bool
    @State private var results: [DiagnosticResult] = []
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Setup Diagnostics")
                        .font(.title2.bold())
                        .foregroundStyle(theme.textPrimary)
                    Text("Checks the active keys, backend, Apple access, Bluetooth, and reports endpoint.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                if results.isEmpty {
                    ProgressView("Running checks...")
                        .frame(maxWidth: .infinity)
                        .padding(30)
                } else {
                    ForEach(results) { result in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: result.state))
                                .foregroundStyle(color(for: result.state))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text(result.detail)
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            if result.state == .fail || result.state == .warning {
                                if result.fixAction != nil || destination(for: result.id) != nil {
                                    Button("Fix") { runFix(for: result) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                } else {
                                    Text(label(for: result.state))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(color(for: result.state))
                                }
                            } else {
                                Text(label(for: result.state))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color(for: result.state))
                            }
                        }
                        .padding(11)
                        if result.id != results.last?.id { Divider() }
                    }
                }
            }
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.cardBorder))

            HStack {
                Spacer()
                Button("Run Again") { runDiagnostics() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.primaryOrange)
                    .disabled(isRunning)
            }
        }
        .padding(24)
        .frame(width: 620, height: 610)
        .background(theme.background)
        .task { runDiagnostics() }
    }

    private func runDiagnostics() {
        guard !isRunning else { return }
        isRunning = true
        results = []
        Task {
            let values = await appState.diagnosticsService.runAll()
            await MainActor.run {
                results = values
                isRunning = false
            }
        }
    }

    private func runFix(for result: DiagnosticResult) {
        if let destination = destination(for: result.id) {
            router.currentDestination = destination
            isPresented = false
            return
        }
        guard let action = result.fixAction else { return }
        Task {
            await action()
            runDiagnostics()
        }
    }

    private func destination(for id: DiagnosticID) -> AppDestination? {
        switch id {
        case .keysFileValid, .privateKeyStored, .hashedAdvKeyValid, .flipperSelected, .bluetoothPermission:
            return .flipperDetail
        case .appleAccessConnected:
            return .settings
        case .backendRunning, .reportsEndpoint:
            return nil
        }
    }

    private func icon(for state: DiagnosticState) -> String {
        switch state {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        case .running: return "clock.fill"
        case .pending: return "circle"
        }
    }

    private func label(for state: DiagnosticState) -> String {
        switch state {
        case .pass: return "Passed"
        case .warning: return "Warning"
        case .fail: return "Failed"
        case .running: return "Running"
        case .pending: return "Pending"
        }
    }

    private func color(for state: DiagnosticState) -> Color {
        switch state {
        case .pass: return theme.successGreen
        case .warning: return theme.warningAmber
        case .fail: return theme.errorRed
        case .running: return theme.primaryOrange
        case .pending: return theme.textSecondary
        }
    }
}

// MARK: - ErrorBanner

struct ErrorBanner: View {
    let message: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warningAmber)
            Text(message).font(.subheadline).foregroundStyle(theme.textPrimary)
            Spacer()
        }
        .padding(12)
        .background(theme.warningAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.warningAmber.opacity(0.3), lineWidth: 1))
    }
}
