import Foundation
import Combine
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published state
    @Published var activeProfile: FlipperProfile?
    @Published var profiles: [FlipperProfile] = []
    @Published var onboardingComplete: Bool
    @Published var backendStatus: BackendStatus = .stopped
    @Published var bleState: BLEScanState = .idle
    @Published var reports: [LocationReport] = []
    @Published var settings: AppSettings

    // MARK: - Services (owned here)
    let keychainService: KeychainService
    let profileStore: ProfileStore
    let reportsStore: ReportsStore
    let settingsStore: SettingsStore
    let backendManager: BackendManager
    let backendClient: BackendClient
    let bleManager: BLEManager
    let refreshService: ReportRefreshService
    let diagnosticsService: SetupDiagnosticsService
    let menuBarController: MenuBarController
    let notificationService: NotificationService
    let geocodingService: GeocodingService
    let keyRotationService: KeyRotationService

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Bootstrap services
        let keychain = KeychainService()
        let profileStore = ProfileStore()
        let reportsStore = ReportsStore()
        let settingsStore = SettingsStore()
        let backendClient = BackendClient()
        let backendManager = BackendManager(client: backendClient)
        let bleManager = BLEManager(profileStore: profileStore)
        let refreshService = ReportRefreshService(
            backendClient: backendClient,
            backendManager: backendManager,
            reportsStore: reportsStore,
            keychainService: keychain,
            profileStore: profileStore
        )
        let diagnosticsService = SetupDiagnosticsService(
            keychainService: keychain,
            backendClient: backendClient,
            backendManager: backendManager,
            profileStore: profileStore
        )
        let menuBarController = MenuBarController()
        let notificationService = NotificationService.shared
        let geocodingService = GeocodingService()
        let keyRotationService = KeyRotationService(
            backendManager: backendManager,
            backendClient: backendClient,
            keychain: keychain,
            profileStore: profileStore
        )

        self.keychainService = keychain
        self.profileStore = profileStore
        self.reportsStore = reportsStore
        self.settingsStore = settingsStore
        self.backendClient = backendClient
        self.backendManager = backendManager
        self.bleManager = bleManager
        self.refreshService = refreshService
        self.diagnosticsService = diagnosticsService
        self.menuBarController = menuBarController
        self.notificationService = notificationService
        self.geocodingService = geocodingService
        self.keyRotationService = keyRotationService

        // Restore persisted state
        if var profile = profileStore.activeProfile(), profile.isBLEConnected {
            // A CoreBluetooth connection never survives process termination.
            // Keep the identifier and last-known telemetry, but start the new
            // app session disconnected until CBCentralManager confirms it.
            profile.isBLEConnected = false
            try? profileStore.updateProfile(profile)
        }
        let savedSettings = settingsStore.settings
        self.settings = savedSettings
        self.onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        self.profiles = profileStore.profiles
        self.activeProfile = profileStore.activeProfile()

        // Load reports for active profile
        if let profile = profileStore.activeProfile() {
            self.reports = reportsStore.reports(forProfile: profile.id)
        }

        setupBindings()

        // Request notification permission on first launch (task 26)
        Task { await notificationService.requestAuthorizationIfNeeded() }
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }

    // MARK: - Private bindings

    private func setupBindings() {
        // Views consume these owned services through AppState. Forward their
        // changes so nested loading, error, BLE, and key-operation state always
        // invalidates the SwiftUI hierarchy immediately.
        refreshService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        bleManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Mirror profileStore.profiles → self.profiles
        profileStore.$profiles
            .receive(on: RunLoop.main)
            .sink { [weak self] newProfiles in
                guard let self else { return }
                self.profiles = newProfiles
                self.activeProfile = newProfiles.first { $0.isActive }
                if let profile = self.activeProfile {
                    self.reports = self.reportsStore.reports(forProfile: profile.id)
                    self.menuBarController.updateStatus(from: profile)
                }
            }
            .store(in: &cancellables)

        // Mirror backendManager.status → self.backendStatus
        backendManager.$status
            .receive(on: RunLoop.main)
            .assign(to: &$backendStatus)

        // Mirror bleManager.scanState → self.bleState
        bleManager.$scanState
            .receive(on: RunLoop.main)
            .assign(to: &$bleState)

        // Mirror settingsStore.settings → self.settings, update refresh interval
        settingsStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] newSettings in
                guard let self else { return }
                self.settings = newSettings
                self.refreshService.setInterval(newSettings.refreshInterval)
            }
            .store(in: &cancellables)

        // When reports store updates, re-read for active profile
        reportsStore.$reportsByProfile
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let profile = self.activeProfile else { return }
                self.reports = self.reportsStore.reports(forProfile: profile.id)
            }
            .store(in: &cancellables)
    }
}
