import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @State private var showClearReportsConfirmation = false
    @State private var showAppleAccess = false
    @State private var appleAccessAccount: String?
    @State private var isCheckingAppleAccess = true
    @State private var operationError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings")
                    .font(.title2.bold())
                    .foregroundStyle(theme.textPrimary)

                section("General") {
                    settingsRow("Refresh interval") {
                        optionMenu(
                            selected: appState.settings.refreshInterval,
                            options: RefreshInterval.allCases.map { ($0, $0.displayName) }
                        ) { value in
                            updateSettings { $0.refreshInterval = value }
                            appState.refreshService.setInterval(value)
                        }
                    }
                    rowDivider
                    settingsRow("Launch at login") {
                        Toggle("", isOn: settingBinding(\.launchAtLogin) { enabled in
                            if enabled { try? SMAppService.mainApp.register() }
                            else { try? SMAppService.mainApp.unregister() }
                        })
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(theme.primaryOrange)
                    }
                    rowDivider
                    settingsRow("Minimize to menu bar") {
                        Toggle("", isOn: settingBinding(\.minimizeToMenuBar))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(theme.primaryOrange)
                    }
                }

                section("Appearance") {
                    settingsRow("Theme") {
                        optionMenu(
                            selected: appState.settings.theme,
                            options: ThemeOption.allCases.map { ($0, $0.displayName) }
                        ) { value in updateSettings { $0.theme = value } }
                    }
                    rowDivider
                    settingsRow("Accent color") {
                        HStack(spacing: 7) {
                            Circle().fill(theme.primaryOrange).frame(width: 12, height: 12)
                            Text(accentDisplayName)
                                .font(.subheadline)
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
                    rowDivider
                    settingsRow("Flipper icon") {
                        HStack(spacing: 8) {
                            ForEach(FlipperIconStyle.allCases, id: \.self) { style in
                                let isSelected = appState.settings.flipperIconStyle == style
                                let selectionColor = Color(hex: style.selectionColorHex)
                                Button {
                                    updateSettings { $0.flipperIconStyle = style }
                                } label: {
                                    VStack(spacing: 5) {
                                        FlipperMiniDevice(style: style)
                                            .frame(width: 54, height: 31)
                                        Text(style.displayName)
                                            .font(.caption2.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(isSelected ? selectionColor : theme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected ? selectionColor.opacity(0.14) : theme.background,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? selectionColor : theme.cardBorder, lineWidth: isSelected ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    rowDivider
                    settingsRow("Default map") {
                        optionMenu(
                            selected: appState.settings.mapDisplayMode,
                            options: MapDisplayMode.allCases.map { ($0, $0.displayName) }
                        ) { value in updateSettings { $0.mapDisplayMode = value } }
                    }
                    rowDivider
                    settingsRow("Distance units") {
                        optionMenu(
                            selected: appState.settings.distanceUnit,
                            options: [(.metric, "Metric (m, km)"), (.imperial, "Imperial (ft, mi)")]
                        ) { value in updateSettings { $0.distanceUnit = value } }
                    }
                }

                section("Notifications") {
                    settingsRow("New Find My report") {
                        settingsToggle(\.notifyOnNewReport)
                    }
                    rowDivider
                    settingsRow("Flipper connects nearby") {
                        settingsToggle(\.notifyFlipperNearby)
                    }
                    rowDivider
                    settingsRow("Low battery") {
                        settingsToggle(\.notifyLowBattery)
                    }
                }

                section("Apple Access") {
                    settingsRow("Find My reports") {
                        if isCheckingAppleAccess {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(
                                appleAccessAccount ?? "Reconnect required",
                                systemImage: appleAccessAccount == nil ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appleAccessAccount == nil ? theme.warningAmber : theme.successGreen)
                        }
                    }
                    rowDivider
                    HStack {
                        Text("Apple credentials and two-factor verification stay inside the local sign-in flow.")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Button(appleAccessAccount == nil ? "Connect Apple Access" : "Sign In Again") {
                            showAppleAccess = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.primaryOrange)
                    }
                }

                section("Backend and Data") {
                    settingsRow("Local backend") {
                        Label(backendStatusText, systemImage: backendStatusIcon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(backendStatusColor)
                    }
                    rowDivider
                    settingsRow("Flipper key folder") {
                        Text(FlipperSDCardService.destinationDirectory)
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                    }
                    rowDivider
                    HStack(spacing: 10) {
                        Button("Restart Backend") {
                            Task { await appState.backendManager.restartBackend() }
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.primaryOrange)

                        Button("Refresh Reports") {
                            Task { await appState.refreshService.triggerManualRefresh() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.primaryOrange)

                        Spacer()

                        Button("Clear Reports", role: .destructive) {
                            showClearReportsConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }

                HStack {
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/Arxhsz")!)
                    } label: {
                        Text("Made by Arxhsz on GitHub")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Open Arxhsz on GitHub")
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(theme.background)
        .navigationTitle("Settings")
        .confirmationDialog("Clear saved location reports?", isPresented: $showClearReportsConfirmation) {
            Button("Clear Reports", role: .destructive) {
                if let profile = appState.activeProfile {
                    do {
                        try appState.reportsStore.clearReports(forProfile: profile.id)
                    } catch {
                        operationError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes locally cached reports for the active profile. It does not remove keys or Apple access.")
        }
        .sheet(isPresented: $showAppleAccess) {
            AppleAccessView(
                onContinue: {
                    showAppleAccess = false
                    Task {
                        await loadAppleAccessStatus()
                        await appState.refreshService.triggerManualRefresh()
                    }
                },
                onBack: { showAppleAccess = false },
                showsCancelButton: true
            )
            .environmentObject(appState)
            .environment(\.appTheme, theme)
            .frame(width: 520, height: 650)
        }
        .task { await loadAppleAccessStatus() }
        .alert("Settings Operation Failed", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "The requested operation could not be completed.")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            VStack(spacing: 0) { content() }
                .padding(16)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.cardBorder))
        }
    }

    private var rowDivider: some View {
        Divider().padding(.vertical, 11)
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            control()
        }
        .frame(minHeight: 26)
    }

    private func optionMenu<Value: Hashable>(
        selected: Value,
        options: [(Value, String)],
        onSelect: @escaping (Value) -> Void
    ) -> some View {
        let selectedLabel = options.first(where: { $0.0 == selected })?.1 ?? "Select"
        return Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    onSelect(option.0)
                } label: {
                    if option.0 == selected {
                        Label(option.1, systemImage: "checkmark")
                    } else {
                        Text(option.1)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedLabel)
                    .foregroundStyle(theme.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.cardBorder))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func settingsToggle(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> some View {
        Toggle("", isOn: settingBinding(keyPath))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(theme.primaryOrange)
    }

    private func settingBinding(
        _ keyPath: WritableKeyPath<AppSettings, Bool>,
        afterChange: ((Bool) -> Void)? = nil
    ) -> Binding<Bool> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { value in
                updateSettings { $0[keyPath: keyPath] = value }
                afterChange?(value)
            }
        )
    }

    private func updateSettings(_ update: (inout AppSettings) -> Void) {
        var settings = appState.settings
        update(&settings)
        appState.settingsStore.update(settings)
    }

    private var accentDisplayName: String {
        switch appState.settings.theme {
        case .system:
            return "System Accent"
        default:
            return appState.settings.theme.displayName
        }
    }

    private func loadAppleAccessStatus() async {
        await appState.backendManager.startBackend()
        let status = try? await appState.backendClient.authStatus()
        appleAccessAccount = status?.connected == true ? status?.accountIdentifier : nil
        isCheckingAppleAccess = false
    }

    private var backendStatusText: String {
        switch appState.backendStatus {
        case .running: return "Running"
        case .starting: return "Starting"
        case .stopped: return "Stopped"
        case .error: return "Error"
        }
    }

    private var backendStatusIcon: String {
        switch appState.backendStatus {
        case .running: return "checkmark.circle.fill"
        case .starting: return "clock.fill"
        case .stopped: return "stop.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var backendStatusColor: Color {
        switch appState.backendStatus {
        case .running: return theme.successGreen
        case .starting: return theme.primaryOrange
        case .stopped: return theme.textSecondary
        case .error: return theme.errorRed
        }
    }
}
