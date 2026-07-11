import Foundation
import CoreBluetooth

@MainActor
final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var discoveredDevices: [BLEDeviceRecord] = []
    @Published var scanState: BLEScanState = .idle
    @Published var connectionState: BLEConnectionState = .idle
    @Published var connectedPeripheral: CBPeripheral?
    @Published var liveRSSI: Int?
    @Published var discoveredServiceUUIDs: [String] = []
    @Published var firmwareVersion: String?
    @Published var batteryLevel: Int?
    @Published var alertAvailable = false
    @Published var alertAnimationToken = 0
    @Published var userMessage: String?

    private let profileStore: ProfileStore
    private let scorer = BLEDeviceScorer()
    private var centralManager: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var scanRequested = false
    private var targetIdentifier: UUID?
    private var alertCharacteristic: CBCharacteristic?
    private var alertResponseCharacteristic: CBCharacteristic?
    private var usesFindMyFlipperAlertProtocol = false
    private var reconnectTask: Task<Void, Never>?

    private let batteryService = CBUUID(string: "180F")
    private let batteryLevelCharacteristic = CBUUID(string: "2A19")
    private let deviceInformationService = CBUUID(string: "180A")
    private let firmwareRevisionCharacteristic = CBUUID(string: "2A26")
    private let softwareRevisionCharacteristic = CBUUID(string: "2A28")
    private let immediateAlertService = CBUUID(string: "1802")
    private let alertLevelCharacteristic = CBUUID(string: "2A06")
    private let findMyFlipperAlertWriteCharacteristic = CBUUID(string: "19ED82AE-ED21-4C9D-4145-228E62FE0000")
    private let findMyFlipperAlertReadCharacteristic = CBUUID(string: "19ED82AE-ED21-4C9D-4145-228E61FE0000")

    init(profileStore: ProfileStore) {
        self.profileStore = profileStore
        super.init()
    }

    func startScan() {
        userMessage = nil
        scanRequested = true
        scanState = .scanning
        connectionState = .scanning
        ensureCentralManager()
        if centralManager?.state == .poweredOn {
            beginScanning()
        }
    }

    func stopScan() {
        scanRequested = false
        centralManager?.stopScan()
        scanState = .idle
        if connectedPeripheral == nil, case .scanning = connectionState {
            connectionState = .idle
        }
    }

    func selectDevice(_ record: BLEDeviceRecord) {
        guard var profile = profileStore.activeProfile() else {
            userMessage = "Create or select a profile before connecting a Flipper."
            return
        }

        // Persist CoreBluetooth's stable peripheral identifier, never the
        // temporary UUID used by a scan-list row.
        profile.bleDeviceID = record.peripheralIdentifier
        profile.bleDeviceName = record.displayName
        if shouldReplaceGenericProfileName(profile.displayName, with: record.displayName) {
            profile.displayName = record.displayName
        }
        profile.lastBLERSSI = record.lastRSSI
        profile.detectedBLEServices = record.detectedServiceUUIDs
        profile.autoReconnect = true
        try? profileStore.updateProfile(profile)

        targetIdentifier = record.peripheralIdentifier
        stopScan()
        if let peripheral = peripherals[record.peripheralIdentifier] {
            connect(peripheral)
        } else {
            reconnectSavedDevice()
        }
    }

    func reconnectSavedDevice() {
        guard let identifier = profileStore.activeProfile()?.bleDeviceID else {
            connectionState = .unavailable("No Flipper is linked to this profile.")
            return
        }
        targetIdentifier = identifier
        userMessage = nil
        ensureCentralManager()
        if centralManager?.state == .poweredOn {
            retrieveOrScanForTarget(identifier)
        }
    }

    func resumeAutoReconnect() {
        guard profileStore.activeProfile()?.autoReconnect == true,
              profileStore.activeProfile()?.bleDeviceID != nil else { return }
        reconnectSavedDevice()
    }

    func forgetSavedDevice() {
        disconnect()
        guard var profile = profileStore.activeProfile() else { return }
        profile.bleDeviceID = nil
        profile.bleDeviceName = nil
        profile.lastBLERSSI = nil
        profile.detectedBLEServices = nil
        profile.firmwareVersion = nil
        profile.batteryLevel = nil
        profile.isBLEConnected = false
        try? profileStore.updateProfile(profile)
        targetIdentifier = nil
        connectionState = .idle
    }

    func scoreDevice(name: String?, rssi: Int, lastSeen: Date = Date()) -> BLEDeviceScore {
        scorer.score(name: name, rssi: rssi, lastSeen: lastSeen)
    }

    func playAlert() {
        alertAnimationToken &+= 1
        guard let peripheral = connectedPeripheral,
              peripheral.state == .connected,
              let alertCharacteristic else {
            userMessage = "This Flipper does not expose a Bluetooth alert characteristic."
            return
        }
        let payload = usesFindMyFlipperAlertProtocol ? Data([0x03, 0xB2, 0x02, 0x00]) : Data([2])
        let writeType: CBCharacteristicWriteType = alertCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(payload, for: alertCharacteristic, type: writeType)
        userMessage = writeType == .withResponse
            ? "Sending alert command to \(peripheral.name ?? "Flipper")..."
            : "Alert command sent to \(peripheral.name ?? "Flipper")."
    }

    func disconnect() {
        reconnectTask?.cancel()
        guard let peripheral = connectedPeripheral else {
            markProfileDisconnected()
            connectionState = .idle
            return
        }
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    private func ensureCentralManager() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    private func beginScanning() {
        guard let centralManager, centralManager.state == .poweredOn else { return }
        centralManager.stopScan()
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        scanState = .scanning
        connectionState = .scanning
    }

    private func retrieveOrScanForTarget(_ identifier: UUID) {
        guard let centralManager, centralManager.state == .poweredOn else { return }
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [identifier]).first {
            peripherals[identifier] = peripheral
            connect(peripheral)
            return
        }

        connectionState = .connecting(profileStore.activeProfile()?.bleDeviceName ?? "Saved Flipper")
        scanRequested = true
        beginScanning()
        let expectedIdentifier = identifier
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.targetIdentifier == expectedIdentifier,
                  self.connectedPeripheral == nil else { return }
            self.scanRequested = false
            self.centralManager?.stopScan()
            self.scanState = .notFound
            self.connectionState = .unavailable("Saved Flipper was not found nearby. Scan and select it again.")
        }
    }

    private func connect(_ peripheral: CBPeripheral) {
        guard let centralManager else { return }
        scanRequested = false
        centralManager.stopScan()
        scanState = .idle
        targetIdentifier = peripheral.identifier
        connectionState = .connecting(peripheral.name ?? profileStore.activeProfile()?.bleDeviceName ?? "Flipper")
        if peripheral.state == .connected {
            handleConnected(peripheral)
        } else {
            centralManager.connect(peripheral, options: nil)
        }
    }

    private func handleConnected(_ peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connected(peripheral.name ?? profileStore.activeProfile()?.bleDeviceName ?? "Flipper")
        userMessage = nil
        liveRSSI = nil
        discoveredServiceUUIDs = []
        firmwareVersion = nil
        batteryLevel = nil
        alertAvailable = false
        alertCharacteristic = nil
        alertResponseCharacteristic = nil
        usesFindMyFlipperAlertProtocol = false
        peripheral.discoverServices(nil)
        peripheral.readRSSI()

        guard var profile = profileStore.activeProfile() else { return }
        profile.bleDeviceID = peripheral.identifier
        let resolvedName = peripheral.name ?? profile.bleDeviceName
        profile.bleDeviceName = resolvedName
        if let resolvedName, shouldReplaceGenericProfileName(profile.displayName, with: resolvedName) {
            profile.displayName = resolvedName
        }
        profile.isBLEConnected = true
        profile.lastBLEConnection = Date()
        try? profileStore.updateProfile(profile)
    }

    private func shouldReplaceGenericProfileName(_ profileName: String, with bleName: String) -> Bool {
        let trimmedBLEName = bleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBLEName.isEmpty else { return false }
        let normalized = profileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty
            || normalized == "my flipper"
            || normalized == "flipper"
            || normalized == "flipper zero"
            || normalized.hasPrefix("findmyflipper-")
            || normalized.hasPrefix("generated-findmyflipper-")
    }

    private func markProfileDisconnected() {
        guard var profile = profileStore.activeProfile() else { return }
        profile.isBLEConnected = false
        try? profileStore.updateProfile(profile)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if let targetIdentifier {
                    retrieveOrScanForTarget(targetIdentifier)
                } else if scanRequested {
                    beginScanning()
                }
            case .poweredOff:
                scanState = .error("Bluetooth is powered off.")
                connectionState = .error("Turn on Bluetooth to connect your Flipper.")
                markProfileDisconnected()
            case .unauthorized:
                scanState = .error("Bluetooth access is not authorized.")
                connectionState = .error("Enable FindMyFlipper in System Settings > Privacy & Security > Bluetooth.")
                markProfileDisconnected()
            case .unsupported:
                scanState = .error("Bluetooth is not supported on this Mac.")
                connectionState = .error("Bluetooth is not supported on this Mac.")
            default:
                connectionState = .connecting(profileStore.activeProfile()?.bleDeviceName ?? "Bluetooth")
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let rssi = RSSI.intValue
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
            let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
            let score = scorer.score(name: name, rssi: rssi, lastSeen: Date())
            peripherals[peripheral.identifier] = peripheral

            if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheral.identifier }) {
                discoveredDevices[index].discoveredName = name
                discoveredDevices[index].lastKnownName = name ?? discoveredDevices[index].lastKnownName
                discoveredDevices[index].lastRSSI = rssi
                discoveredDevices[index].detectedServiceUUIDs = serviceUUIDs
                discoveredDevices[index].manufacturerData = manufacturerData
                discoveredDevices[index].lastSeenBLE = Date()
                discoveredDevices[index].score = score
            } else {
                discoveredDevices.append(BLEDeviceRecord(
                    id: peripheral.identifier,
                    peripheralIdentifier: peripheral.identifier,
                    lastKnownName: name,
                    discoveredName: name,
                    lastRSSI: rssi,
                    detectedServiceUUIDs: serviceUUIDs,
                    manufacturerData: manufacturerData,
                    lastSeenBLE: Date(),
                    selectedByUser: targetIdentifier == peripheral.identifier,
                    autoReconnectEnabled: true,
                    score: score
                ))
            }
            discoveredDevices.sort { lhs, rhs in
                if lhs.score != rhs.score { return scorePriority(lhs.score) < scorePriority(rhs.score) }
                return lhs.lastRSSI > rhs.lastRSSI
            }

            if peripheral.identifier == targetIdentifier {
                connect(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in handleConnected(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectedPeripheral = nil
            markProfileDisconnected()
            connectionState = .error(error?.localizedDescription ?? "Could not connect to the selected Flipper.")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectedPeripheral = nil
            alertCharacteristic = nil
            alertResponseCharacteristic = nil
            usesFindMyFlipperAlertProtocol = false
            alertAvailable = false
            markProfileDisconnected()
            connectionState = .unavailable(error?.localizedDescription ?? "Flipper disconnected.")

            guard profileStore.activeProfile()?.autoReconnect == true,
                  profileStore.activeProfile()?.bleDeviceID == peripheral.identifier else { return }
            reconnectTask?.cancel()
            reconnectTask = Task { [weak self = self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.reconnectSavedDevice()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                userMessage = "Connected, but service discovery failed: \(error.localizedDescription)"
                return
            }
            let services = peripheral.services ?? []
            discoveredServiceUUIDs = services.map { $0.uuid.uuidString }
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
            if var profile = profileStore.activeProfile() {
                profile.detectedBLEServices = discoveredServiceUUIDs
                try? profileStore.updateProfile(profile)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard error == nil else { return }
            for characteristic in service.characteristics ?? [] {
                switch characteristic.uuid {
                case batteryLevelCharacteristic, firmwareRevisionCharacteristic, softwareRevisionCharacteristic:
                    peripheral.readValue(for: characteristic)
                case alertLevelCharacteristic:
                    if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                        alertCharacteristic = characteristic
                        alertAvailable = true
                    }
                case findMyFlipperAlertWriteCharacteristic:
                    if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                        alertCharacteristic = characteristic
                        usesFindMyFlipperAlertProtocol = true
                        alertAvailable = true
                    }
                case findMyFlipperAlertReadCharacteristic:
                    alertResponseCharacteristic = characteristic
                    if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    } else if characteristic.properties.contains(.read) {
                        peripheral.readValue(for: characteristic)
                    }
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard error == nil, let data = characteristic.value else { return }
            if characteristic.uuid == batteryLevelCharacteristic, let level = data.first {
                batteryLevel = min(Int(level), 100)
                if var profile = profileStore.activeProfile() {
                    profile.batteryLevel = batteryLevel
                    try? profileStore.updateProfile(profile)
                }
            } else if characteristic.uuid == firmwareRevisionCharacteristic || characteristic.uuid == softwareRevisionCharacteristic,
                      let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty {
                firmwareVersion = value
                if var profile = profileStore.activeProfile() {
                    profile.firmwareVersion = value
                    try? profileStore.updateProfile(profile)
                }
            } else if characteristic.uuid == findMyFlipperAlertReadCharacteristic {
                if data.starts(with: [0x02, 0x22, 0x00]) {
                    userMessage = "Flipper confirmed the alert command."
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == findMyFlipperAlertWriteCharacteristic || characteristic.uuid == alertLevelCharacteristic else { return }
            if let error {
                userMessage = "Flipper rejected the alert command: \(error.localizedDescription)"
            } else {
                userMessage = "Alert command delivered to \(peripheral.name ?? "Flipper")."
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == findMyFlipperAlertReadCharacteristic, let error else { return }
            userMessage = "Connected, but alert responses are unavailable: \(error.localizedDescription)"
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in
            guard error == nil else { return }
            liveRSSI = RSSI.intValue
            if var profile = profileStore.activeProfile() {
                profile.lastBLERSSI = RSSI.intValue
                try? profileStore.updateProfile(profile)
            }
        }
    }

    private func scorePriority(_ score: BLEDeviceScore) -> Int {
        switch score {
        case .recommended: return 0
        case .possibleFlipper: return 1
        case .unknown: return 2
        case .weak: return 3
        }
    }
}
