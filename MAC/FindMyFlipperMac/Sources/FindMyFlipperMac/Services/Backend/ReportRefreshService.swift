import Foundation
import Combine

@MainActor
final class ReportRefreshService: ObservableObject {
    @Published var lastRefreshed: Date?
    @Published var isRefreshing: Bool = false
    @Published var refreshError: RefreshError?

    private let backendClient: BackendClient
    private let backendManager: BackendManager
    private let reportsStore: ReportsStore
    private let keychainService: KeychainService
    private let profileStore: ProfileStore

    private var timerCancellable: AnyCancellable?
    private var currentInterval: RefreshInterval = .fifteenMin

    init(backendClient: BackendClient,
         backendManager: BackendManager,
         reportsStore: ReportsStore,
         keychainService: KeychainService,
         profileStore: ProfileStore) {
        self.backendClient = backendClient
        self.backendManager = backendManager
        self.reportsStore = reportsStore
        self.keychainService = keychainService
        self.profileStore = profileStore
    }

    // MARK: - Manual refresh

    func triggerManualRefresh() async {
        guard !isRefreshing else { return }
        await performRefresh()
    }

    // MARK: - Automatic scheduling

    func setInterval(_ interval: RefreshInterval) {
        currentInterval = interval
        stopAutomaticRefresh()
        guard interval != .manual else { return }
        startAutomaticRefresh()
    }

    func startAutomaticRefresh() {
        guard currentInterval != .manual else { return }
        let seconds = Double(currentInterval.rawValue) * 60
        timerCancellable = Timer.publish(every: seconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.performRefresh() }
            }
    }

    func stopAutomaticRefresh() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // MARK: - Core refresh logic

    private func performRefresh() async {
        // A clean first-run/onboarding state has no active profile yet. Do not
        // wake or diagnose the backend until there is a key/profile to refresh.
        guard let profile = profileStore.activeProfile() else {
            refreshError = nil
            return
        }

        switch backendManager.status {
        case .running, .starting:
            if !(await backendManager.checkHealth()) {
                await backendManager.startBackend()
            }
        default:
            break
        }

        guard backendManager.status == .running else {
            refreshError = .backendNotRunning
            return
        }

        // Load the public key metadata linked by the profile.
        let keyRecord: FindMyKeyRecord
        do {
            keyRecord = try profileStore.loadKeyRecord(id: profile.findMyKeyID)
        } catch {
            refreshError = .unknown("Could not load key record.")
            return
        }

        // Profiles reference FindMyKeyRecord.id; Keychain is addressed by the
        // record's separate keychainKeyID.
        let privateKey: String
        do {
            privateKey = try keychainService.loadPrivateKey(forID: keyRecord.keychainKeyID)
        } catch {
            refreshError = .unknown("Could not access private key from Keychain.")
            return
        }

        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }

        do {
            let response = try await backendClient.fetchDecryptedReports(
                hashedAdvKey: keyRecord.hashedAdvKeyBase64,
                privateKeyBase64: privateKey
            )
            let newReports = response.reports.map {
                $0.toLocationReport(profileID: profile.id)
            }
            try reportsStore.insert(newReports, forProfile: profile.id)
            lastRefreshed = Date()
        } catch BackendError.authRequired {
            refreshError = .authRequired
        } catch BackendError.networkUnavailable {
            refreshError = .networkUnavailable
        } catch BackendError.notRunning {
            refreshError = .backendNotRunning
        } catch {
            refreshError = .unknown(error.localizedDescription)
        }
    }
}
