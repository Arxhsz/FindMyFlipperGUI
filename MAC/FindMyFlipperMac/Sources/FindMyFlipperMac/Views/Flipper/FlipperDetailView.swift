import SwiftUI
import AppKit

private struct KeyOperationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct FlipperDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @State private var isRenaming = false
    @State private var renameValue = ""
    @State private var isConfirmingKeyRotation = false
    @State private var isRotatingKeys = false
    @State private var flipperKeyFiles: [String] = []
    @State private var matchingFlipperFilename: String?
    @State private var isLoadingFlipperKeys = false
    @State private var keyOperationAlert: KeyOperationAlert?

    private var profile: FlipperProfile? { appState.activeProfile }
    private var manager: BLEManager { appState.bleManager }
    private var isConnected: Bool { manager.connectedPeripheral != nil && profile?.isBLEConnected == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                connectionCard

                if !isConnected && (manager.scanState == .scanning || !manager.discoveredDevices.isEmpty) {
                    nearbyDevices
                }

                deviceDetails
                usbKeysCard
                activeKeyCard
                actions
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(theme.background)
        .navigationTitle("Flipper")
        .alert("Rename Profile", isPresented: $isRenaming) {
            TextField("Profile name", text: $renameValue)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { renameProfile() }
                .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("This changes the profile name shown throughout FindMyFlipper.")
        }
        .confirmationDialog(
            "Replace all keys for this Flipper?",
            isPresented: $isConfirmingKeyRotation,
            titleVisibility: .visible
        ) {
            Button("Generate New Keys and Delete Old Keys", role: .destructive) {
                rotateKeys()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app will first create and verify a replacement, copy it to the connected Flipper, and make it active. It will then delete older .keys files from /ext/apps_data/findmy and unreferenced key records from this Mac.")
        }
        .alert(item: $keyOperationAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .task { await refreshFlipperKeys() }
    }

    private var header: some View {
        HStack(spacing: 24) {
            FlipperProductImage()
                .frame(width: 250, height: 125)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(profile?.displayName ?? "No Flipper Profile")
                        .font(.title2.bold())
                        .foregroundStyle(theme.textPrimary)
                    if profile != nil {
                        Button {
                            renameValue = profile?.displayName ?? ""
                            isRenaming = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.primaryOrange)
                        .help("Rename profile")
                    }
                }
                Label(connectionTitle, systemImage: connectionIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(connectionColor)
                if let name = profile?.bleDeviceName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                if let identifier = profile?.bleDeviceID {
                    Text(identifier.uuidString)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
    }

    private var connectionCard: some View {
        GlassCard {
            HStack(spacing: 18) {
                statusMetric("Connection", connectionTitle, icon: connectionIcon, color: connectionColor)
                Divider().frame(height: 54)
                statusMetric("Signal", signalText, icon: "cellularbars", color: signalColor)
                Divider().frame(height: 54)
                statusMetric("Battery", batteryText, icon: batteryIcon, color: batteryColor)
                Divider().frame(height: 54)
                statusMetric("Last connected", lastConnectionText, icon: "clock", color: theme.textSecondary)
            }
        }
    }

    private var nearbyDevices: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nearby Bluetooth Devices")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if manager.scanState == .scanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            VStack(spacing: 0) {
                if manager.discoveredDevices.isEmpty {
                    Text("Keep the Flipper awake and nearby while scanning.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ForEach(manager.discoveredDevices.prefix(8)) { device in
                        HStack(spacing: 12) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(device.score == .recommended ? theme.successGreen : theme.primaryOrange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text("\(device.lastRSSI) dBm · \(device.peripheralIdentifier.uuidString.prefix(8))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Button("Connect") { manager.selectDevice(device) }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.primaryOrange)
                        }
                        .padding(12)
                        if device.id != manager.discoveredDevices.prefix(8).last?.id { Divider() }
                    }
                }
            }
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.cardBorder))
        }
    }

    private var deviceDetails: some View {
        GlassCard {
            VStack(spacing: 14) {
                detailRow("Device name", profile?.bleDeviceName ?? "Not selected")
                Divider()
                detailRow("CoreBluetooth identifier", profile?.bleDeviceID?.uuidString ?? "Not selected", monospaced: true)
                Divider()
                detailRow("Generated Find My MAC", profile?.generatedFindMyMac ?? "No key linked", monospaced: true)
                Divider()
                detailRow("Firmware", manager.firmwareVersion ?? profile?.firmwareVersion ?? "Not exposed over Bluetooth")
                Divider()
                detailRow("Detected services", servicesText)
                Divider()
                detailRow("Alert support", manager.alertAvailable ? "Available" : "Not exposed by this Bluetooth mode")
            }
        }
    }

    private var usbKeysCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: FlipperSDCardService.isFlipperConnected ? "externaldrive.fill.badge.checkmark" : "cable.connector")
                        .font(.title2)
                        .foregroundStyle(FlipperSDCardService.isFlipperConnected ? theme.successGreen : theme.primaryOrange)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Flipper microSD Keys")
                            .font(.headline)
                            .foregroundStyle(theme.textPrimary)
                        Text(FlipperSDCardService.destinationDirectory)
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if isLoadingFlipperKeys {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(FlipperSDCardService.isFlipperConnected ? "USB CONNECTED" : "USB DISCONNECTED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(FlipperSDCardService.isFlipperConnected ? theme.successGreen : theme.warningAmber)
                    }
                }

                Divider()

                if !FlipperSDCardService.isFlipperConnected {
                    Label("Connect with a data-capable USB cable and quit qFlipper.", systemImage: "cable.connector")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                } else if flipperKeyFiles.isEmpty && !isLoadingFlipperKeys {
                    Label("No .keys files found on the connected Flipper.", systemImage: "doc.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(theme.warningAmber)
                } else {
                    VStack(spacing: 8) {
                        ForEach(flipperKeyFiles, id: \.self) { filename in
                            HStack(spacing: 10) {
                                Image(systemName: filename == matchingFlipperFilename ? "checkmark.circle.fill" : "doc.text")
                                    .foregroundStyle(filename == matchingFlipperFilename ? theme.successGreen : theme.textSecondary)
                                Text(filename)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                if filename == matchingFlipperFilename {
                                    Text("ACTIVE")
                                        .font(.caption2.bold())
                                        .foregroundStyle(theme.successGreen)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await refreshFlipperKeys() }
                    } label: {
                        Label("Refresh microSD", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingFlipperKeys || !FlipperSDCardService.isFlipperConnected)

                    Spacer()

                    Button {
                        isConfirmingKeyRotation = true
                    } label: {
                        Label(isRotatingKeys ? "Replacing Keys..." : "Replace Keys", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.errorRed)
                    .disabled(isRotatingKeys || !FlipperSDCardService.isFlipperConnected || profile == nil)
                }
            }
        }
    }

    private var activeKeyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Active Find My Identity", systemImage: "key.fill")
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    if activeKeyRecord != nil {
                        Text(isActiveKeyNewest ? "ACTIVE · NEWEST" : "ACTIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.successGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.successGreen.opacity(0.12), in: Capsule())
                    }
                }
                if let record = activeKeyRecord {
                    detailRow("File", record.sourceFileName, monospaced: true)
                    Divider()
                    detailRow("Imported", record.importedAt.formatted(date: .abbreviated, time: .standard))
                    Divider()
                    detailRow("Generated Find My MAC", record.generatedFindMyMac, monospaced: true)
                    Divider()
                    HStack {
                        Text("microSD match")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Label(
                            matchingFlipperFilename.map { "Verified as \($0)" } ?? "Identity not found",
                            systemImage: matchingFlipperFilename == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(matchingFlipperFilename == nil ? theme.warningAmber : theme.successGreen)
                    }
                } else {
                    Text("The active profile's key metadata could not be loaded. Re-import or replace its keys before refreshing reports.")
                        .font(.subheadline)
                        .foregroundStyle(theme.errorRed)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if isConnected {
                    Button {
                        manager.playAlert()
                    } label: {
                        Label(manager.alertAvailable ? "Play Alert" : "Alert Unavailable", systemImage: "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.primaryOrange)
                    .disabled(!manager.alertAvailable)

                    Button {
                        manager.disconnect()
                    } label: {
                        Text("Disconnect")
                            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                    }
                        .buttonStyle(.bordered)
                        .tint(theme.primaryOrange)
                        .frame(maxWidth: .infinity)
                } else {
                    if profile?.bleDeviceID != nil {
                        Button {
                            manager.reconnectSavedDevice()
                        } label: {
                            Label("Connect Saved Flipper", systemImage: "link")
                                .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.primaryOrange)
                    }

                    Button {
                        manager.startScan()
                    } label: {
                        Label(manager.scanState == .scanning ? "Scanning..." : "Scan Nearby", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.primaryOrange)
                }
            }

            if profile?.bleDeviceID != nil {
                Button(role: .destructive) { manager.forgetSavedDevice() } label: {
                    Label("Forget Saved Device", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.errorRed)
                        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                        .background(theme.errorRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(theme.errorRed.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activeKeyRecord: FindMyKeyRecord? {
        guard let id = profile?.findMyKeyID else { return nil }
        return try? appState.profileStore.loadKeyRecord(id: id)
    }

    private var isActiveKeyNewest: Bool {
        activeKeyRecord?.id == appState.profileStore.keyRecordsNewestFirst.first?.id
    }

    private func renameProfile() {
        guard var profile else { return }
        let name = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        profile.displayName = name
        do {
            try appState.profileStore.updateProfile(profile)
        } catch {
            manager.userMessage = "Could not rename the profile: \(error.localizedDescription)"
        }
    }

    private func rotateKeys() {
        isRotatingKeys = true
        Task {
            do {
                let result = try await appState.keyRotationService.rotateActiveProfileKeys()
                await refreshFlipperKeys()
                keyOperationAlert = KeyOperationAlert(
                    title: "Keys Replaced",
                    message: "\(result.activeFilename) is active on this Mac and the Flipper. Deleted \(result.removedMacRecords) old Mac record(s) and \(result.removedFlipperFiles) old Flipper file(s)."
                )
            } catch {
                await refreshFlipperKeys()
                keyOperationAlert = KeyOperationAlert(title: "Key Replacement Failed", message: error.localizedDescription)
            }
            isRotatingKeys = false
        }
    }

    private func refreshFlipperKeys() async {
        guard FlipperSDCardService.isFlipperConnected else {
            flipperKeyFiles = []
            matchingFlipperFilename = nil
            return
        }
        isLoadingFlipperKeys = true
        defer { isLoadingFlipperKeys = false }
        do {
            flipperKeyFiles = try await FlipperSDCardService.listKeysFiles()
            if let record = activeKeyRecord {
                matchingFlipperFilename = try await FlipperSDCardService.matchingKeysFilename(
                    hashedAdvKeyBase64: record.hashedAdvKeyBase64
                )
            } else {
                matchingFlipperFilename = nil
            }
        } catch {
            flipperKeyFiles = []
            matchingFlipperFilename = nil
            keyOperationAlert = KeyOperationAlert(title: "Could Not Read microSD", message: error.localizedDescription)
        }
    }

    private func statusMetric(_ title: String, _ value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var connectionTitle: String {
        switch manager.connectionState {
        case .idle: return profile?.bleDeviceID == nil ? "Not linked" : "Disconnected"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .unavailable: return "Unavailable"
        case .error: return "Connection error"
        }
    }

    private var connectionIcon: String {
        switch manager.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .scanning: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        default: return "circle.fill"
        }
    }

    private var connectionColor: Color {
        switch manager.connectionState {
        case .connected: return theme.successGreen
        case .connecting, .scanning: return theme.primaryOrange
        case .error: return theme.errorRed
        default: return theme.textSecondary
        }
    }

    private var signalText: String {
        guard let rssi = manager.liveRSSI ?? profile?.lastBLERSSI else { return "Not available" }
        let prefix = isConnected ? "" : "Last known: "
        switch rssi {
        case (-55)...: return "\(prefix)Excellent (\(rssi) dBm)"
        case (-67)...: return "\(prefix)Strong (\(rssi) dBm)"
        case (-75)...: return "\(prefix)Fair (\(rssi) dBm)"
        default: return "\(prefix)Weak (\(rssi) dBm)"
        }
    }

    private var signalColor: Color {
        guard let rssi = manager.liveRSSI ?? profile?.lastBLERSSI else { return theme.textSecondary }
        if rssi >= -67 { return theme.successGreen }
        if rssi >= -75 { return theme.warningAmber }
        return theme.errorRed
    }

    private var batteryText: String {
        guard let level = manager.batteryLevel ?? profile?.batteryLevel else { return "Not exposed" }
        return isConnected ? "\(level)%" : "Last known: \(level)%"
    }

    private var batteryIcon: String {
        BatteryDisplay.percentSymbolName(for: manager.batteryLevel ?? profile?.batteryLevel)
    }

    private var batteryColor: Color {
        BatteryDisplay.color(for: manager.batteryLevel ?? profile?.batteryLevel, theme: theme)
    }

    private var lastConnectionText: String {
        if isConnected { return "Now" }
        guard let date = profile?.lastBLEConnection else { return "No successful connection" }
        return date.formatted(.relative(presentation: .named))
    }

    private var servicesText: String {
        let services = manager.discoveredServiceUUIDs.isEmpty
            ? (profile?.detectedBLEServices ?? [])
            : manager.discoveredServiceUUIDs
        return services.isEmpty ? "None discovered" : services.joined(separator: ", ")
    }
}

struct FlipperProductImage: View {
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                FlipperGlyphIcon()
                    .frame(width: 86, height: 50)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard image == nil else { return }
            image = await FlipperProductImageLoader.load()
        }
        .accessibilityLabel("Flipper Zero")
    }
}
