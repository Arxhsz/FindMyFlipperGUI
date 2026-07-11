import SwiftUI

// MARK: - NoReportsView

struct NoReportsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @State private var showAppleAccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.softOrangeSurface)
                            .frame(width: 72, height: 72)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(theme.primaryOrange)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No Find My Reports Yet")
                            .font(.title2.bold())
                            .foregroundStyle(theme.textPrimary)
                        Text("Your setup is ready to receive encrypted location reports when nearby Apple devices detect your Flipper.")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                if let error = appState.refreshService.refreshError {
                    recoveryBanner(for: error)
                }

                Divider()

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Before refreshing")
                            .font(.headline)
                            .foregroundStyle(theme.textPrimary)
                        checkRow("Run the FindMyFlipper app on the Flipper.")
                        checkRow("Confirm the active .keys identity is on its microSD card.")
                        checkRow("Use a 1 second beacon interval and higher transmit power.")
                        checkRow("Allow time near public foot traffic for the Find My network to observe it.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 190)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Report access")
                            .font(.headline)
                            .foregroundStyle(theme.textPrimary)
                        setupRow("Private key", value: activeKeyAvailable ? "In Keychain" : "Needs attention", ok: activeKeyAvailable)
                        setupRow("Bluetooth", value: appState.activeProfile?.isBLEConnected == true ? "Connected" : "Not required", ok: true)
                        setupRow("Local backend", value: appState.backendStatus == .running ? "Running" : "Will start on refresh", ok: true)

                        PrimaryButton("Refresh Reports", icon: "arrow.triangle.2.circlepath", isLoading: appState.refreshService.isRefreshing) {
                            Task {
                                await appState.backendManager.startBackend()
                                await appState.refreshService.triggerManualRefresh()
                            }
                        }
                        .frame(width: 190)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(theme.background)
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

    private func checkRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(theme.primaryOrange)
            Text(text)
                .font(.subheadline).foregroundStyle(theme.textPrimary)
        }
    }

    private var activeKeyAvailable: Bool {
        guard let profile = appState.activeProfile,
              let record = try? appState.profileStore.loadKeyRecord(id: profile.findMyKeyID) else { return false }
        return appState.keychainService.privateKeyExists(forID: record.keychainKeyID)
    }

    private func setupRow(_ title: String, value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? theme.successGreen : theme.warningAmber)
            Text(title).font(.subheadline).foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textPrimary)
        }
    }

    @ViewBuilder
    private func recoveryBanner(for error: RefreshError) -> some View {
        HStack(spacing: 14) {
            Image(systemName: error == .authRequired ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(theme.warningAmber)
            VStack(alignment: .leading, spacing: 3) {
                Text(error == .authRequired ? "Apple access needs to be reconnected" : "Reports could not be refreshed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            if error == .authRequired {
                Button("Reconnect Apple Access") { showAppleAccess = true }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.primaryOrange)
            } else if error == .backendNotRunning || error == .networkUnavailable {
                Button("Restart Backend") {
                    Task { await appState.backendManager.startBackend() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(theme.warningAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.warningAmber.opacity(0.35)))
    }
}

// MARK: - ErrorRecoveryView

struct ErrorRecoveryView: View {
    enum ErrorContext {
        case backendOffline
        case authMissing
        case keychainAccessFailure
    }

    let context: ErrorContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.appTheme) private var theme

    private var icon: String {
        switch context {
        case .backendOffline: return "server.rack"
        case .authMissing: return "person.crop.circle.badge.exclamationmark"
        case .keychainAccessFailure: return "lock.trianglebadge.exclamationmark"
        }
    }

    private var title: String {
        switch context {
        case .backendOffline: return "Backend Offline"
        case .authMissing: return "Authentication Required"
        case .keychainAccessFailure: return "Keychain Access Failed"
        }
    }

    private var message: String {
        switch context {
        case .backendOffline:
            return "The local Python backend isn't running. This is needed to fetch Find My reports."
        case .authMissing:
            return "Your Apple account is not connected. Reconnect to fetch location reports."
        case .keychainAccessFailure:
            return "Could not access the private key from Keychain. You may need to re-import your .keys file."
        }
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(theme.errorRed.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundStyle(theme.errorRed)
                }
                VStack(spacing: 8) {
                    Text(title).font(.title2).fontWeight(.bold).foregroundStyle(theme.textPrimary)
                    Text(message).font(.subheadline).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
                }
                actionButtons
            }
            .padding(40)
            .frame(maxWidth: 400)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch context {
        case .backendOffline:
            PrimaryButton("Restart Backend", icon: "play.fill") {
                Task { await appState.backendManager.startBackend() }
            }
        case .authMissing:
            PrimaryButton("Open Apple Access", icon: "person.badge.plus") {
                router.currentDestination = .settings
            }
        case .keychainAccessFailure:
            PrimaryButton("Open Key Management", icon: "doc.badge.plus") {
                router.currentDestination = .flipperDetail
            }
        }
    }
}
