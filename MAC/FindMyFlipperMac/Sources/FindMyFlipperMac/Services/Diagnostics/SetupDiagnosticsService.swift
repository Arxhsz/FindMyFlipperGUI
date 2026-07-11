import Foundation
import CoreBluetooth

@MainActor
final class SetupDiagnosticsService: NSObject, ObservableObject {
    private let keychainService: KeychainService
    private let backendClient: BackendClient
    private let backendManager: BackendManager
    private let profileStore: ProfileStore
    private var centralManager: CBCentralManager?
    private var bluetoothState: CBManagerAuthorization = .notDetermined

    init(keychainService: KeychainService,
         backendClient: BackendClient,
         backendManager: BackendManager,
         profileStore: ProfileStore) {
        self.keychainService = keychainService
        self.backendClient = backendClient
        self.backendManager = backendManager
        self.profileStore = profileStore
        super.init()
    }

    /// Run all diagnostics. Returns exactly DiagnosticID.allCases.count results in allCases order.
    func runAll() async -> [DiagnosticResult] {
        await withTaskGroup(of: (DiagnosticID, DiagnosticResult).self) { group in
            for id in DiagnosticID.allCases {
                group.addTask { [self] in
                    let result = await self.run(id)
                    return (id, result)
                }
            }
            var map: [DiagnosticID: DiagnosticResult] = [:]
            for await (id, result) in group {
                map[id] = result
            }
            // Return in canonical order
            return DiagnosticID.allCases.compactMap { map[$0] }
        }
    }

    /// Run a single diagnostic by ID.
    func run(_ id: DiagnosticID) async -> DiagnosticResult {
        switch id {
        case .keysFileValid:
            return checkKeysFileValid()
        case .privateKeyStored:
            return checkPrivateKeyStored()
        case .hashedAdvKeyValid:
            return checkHashedAdvKeyValid()
        case .appleAccessConnected:
            return await checkAppleAccessConnected()
        case .backendRunning:
            return checkBackendRunning()
        case .bluetoothPermission:
            return checkBluetoothPermission()
        case .flipperSelected:
            return checkFlipperSelected()
        case .reportsEndpoint:
            return await checkReportsEndpoint()
        }
    }

    // MARK: - Individual checks

    private func checkKeysFileValid() -> DiagnosticResult {
        guard let profile = profileStore.activeProfile(),
              let record = try? profileStore.loadKeyRecord(id: profile.findMyKeyID),
              !record.hashedAdvKeyBase64.isEmpty else {
            return DiagnosticResult(
                id: .keysFileValid, title: "Keys file valid",
                state: .fail, detail: "No valid keys file linked to the active profile.",
                fixAction: nil
            )
        }
        return DiagnosticResult(id: .keysFileValid, title: "Keys file valid", state: .pass, detail: "Keys file is linked and valid.")
    }

    private func checkPrivateKeyStored() -> DiagnosticResult {
        guard let profile = profileStore.activeProfile() else {
            return DiagnosticResult(id: .privateKeyStored, title: "Private key stored", state: .fail, detail: "No active profile.")
        }
        guard let record = try? profileStore.loadKeyRecord(id: profile.findMyKeyID) else {
            return DiagnosticResult(
                id: .privateKeyStored, title: "Private key stored", state: .fail,
                detail: "No key record found for the active profile.",
                fixAction: nil
            )
        }
        // The private key is stored under FindMyKeyRecord.keychainKeyID, not FindMyKeyRecord.id
        let exists = keychainService.privateKeyExists(forID: record.keychainKeyID)
        if exists {
            return DiagnosticResult(id: .privateKeyStored, title: "Private key stored", state: .pass, detail: "Private key is secured in Keychain.")
        }
        return DiagnosticResult(
            id: .privateKeyStored, title: "Private key stored", state: .fail,
            detail: "Private key not found in Keychain. Re-import your .keys file.",
            fixAction: nil
        )
    }

    private func checkHashedAdvKeyValid() -> DiagnosticResult {
        guard let profile = profileStore.activeProfile(),
              let record = try? profileStore.loadKeyRecord(id: profile.findMyKeyID) else {
            return DiagnosticResult(id: .hashedAdvKeyValid, title: "Hashed adv key valid", state: .fail, detail: "No key record found.")
        }
        let key = record.hashedAdvKeyBase64
        let isValidBase64 = Data(base64Encoded: key) != nil && !key.isEmpty
        if isValidBase64 {
            return DiagnosticResult(id: .hashedAdvKeyValid, title: "Hashed adv key valid", state: .pass, detail: "Hashed advertisement key is valid Base64.")
        }
        return DiagnosticResult(id: .hashedAdvKeyValid, title: "Hashed adv key valid", state: .fail, detail: "Hashed advertisement key is not valid Base64.")
    }

    private func checkAppleAccessConnected() async -> DiagnosticResult {
        do {
            let status = try await backendClient.authStatus()
            if status.connected {
                return DiagnosticResult(id: .appleAccessConnected, title: "Apple access connected", state: .pass, detail: "Apple account is connected.")
            }
            return DiagnosticResult(
                id: .appleAccessConnected, title: "Apple access connected", state: .fail,
                detail: "Apple account not connected. Go to Settings > Find My Reports > Reconnect.",
                fixAction: nil
            )
        } catch {
            return DiagnosticResult(id: .appleAccessConnected, title: "Apple access connected", state: .fail, detail: "Could not reach backend to check auth status.")
        }
    }

    private func checkBackendRunning() -> DiagnosticResult {
        if backendManager.status == .running {
            return DiagnosticResult(id: .backendRunning, title: "Backend running", state: .pass, detail: "Local backend is running.")
        }
        return DiagnosticResult(
            id: .backendRunning, title: "Backend running", state: .fail,
            detail: "Backend is not running.",
            fixAction: { [weak self] in await self?.backendManager.startBackend() }
        )
    }

    private func checkBluetoothPermission() -> DiagnosticResult {
        let auth = CBCentralManager.authorization
        switch auth {
        case .allowedAlways:
            return DiagnosticResult(id: .bluetoothPermission, title: "Bluetooth permission", state: .pass, detail: "Bluetooth access is granted.")
        case .restricted:
            return DiagnosticResult(id: .bluetoothPermission, title: "Bluetooth permission", state: .fail, detail: "Bluetooth is restricted by a system policy.")
        case .denied:
            return DiagnosticResult(id: .bluetoothPermission, title: "Bluetooth permission", state: .fail, detail: "Bluetooth access was denied. Enable it in System Settings > Privacy & Security > Bluetooth.")
        default:
            return DiagnosticResult(id: .bluetoothPermission, title: "Bluetooth permission", state: .warning, detail: "Bluetooth permission not yet determined. Tap 'Scan for Flipper' to request access.")
        }
    }

    private func checkFlipperSelected() -> DiagnosticResult {
        guard let profile = profileStore.activeProfile() else {
            return DiagnosticResult(id: .flipperSelected, title: "Flipper selected", state: .fail, detail: "No active profile.")
        }
        if profile.bleDeviceID != nil {
            return DiagnosticResult(id: .flipperSelected, title: "Flipper selected", state: .pass, detail: "A Flipper Zero is linked to this profile.")
        }
        return DiagnosticResult(
            id: .flipperSelected, title: "Flipper selected", state: .warning,
            detail: "No Flipper Zero selected. You can finish setup and link Bluetooth from the Flipper page later.",
            fixAction: nil
        )
    }

    private func checkReportsEndpoint() async -> DiagnosticResult {
        do {
            let health = try await backendClient.health()
            if health.status == "ok" {
                return DiagnosticResult(id: .reportsEndpoint, title: "Reports endpoint", state: .pass, detail: "Backend reports endpoint is reachable.")
            }
        } catch {}
        return DiagnosticResult(
            id: .reportsEndpoint, title: "Reports endpoint", state: .fail,
            detail: "Reports endpoint is not reachable. Make sure the backend is running.",
            fixAction: { [weak self] in await self?.backendManager.startBackend() }
        )
    }
}
