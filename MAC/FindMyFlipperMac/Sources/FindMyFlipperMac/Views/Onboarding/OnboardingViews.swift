import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - OnboardingContainerView

struct OnboardingContainerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @State private var currentStep = 1
    private let totalSteps = 5

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Step label
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 40)
                    .padding(.bottom, 24)

                // Step content
                VStack {
                    Group {
                        switch currentStep {
                        case 1: WelcomePrivacyView(onContinue: goForward)
                        case 2: ImportKeysView(onContinue: goForward, onBack: goBack)
                        case 3: AppleAccessView(onContinue: goForward, onBack: goBack)
                        case 4: ChooseFlipperBLEView(onContinue: goForward, onBack: goBack)
                        case 5: TestSetupView(onFinish: finish, onBack: goBack)
                        default: EmptyView()
                        }
                    }
                    .frame(maxWidth: 500, minHeight: 420)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(currentStep)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: currentStep)

                Spacer()
            }

            if currentStep > 1 {
                VStack {
                    HStack {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.borderless)
                        .help("Previous onboarding step")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 30)
                .padding(.leading, 28)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func goForward() {
        guard currentStep < totalSteps else { finish(); return }
        withAnimation { currentStep += 1 }
    }

    private func goBack() {
        guard currentStep > 1 else { return }
        withAnimation { currentStep -= 1 }
    }

    private func finish() {
        appState.completeOnboarding()
    }
}

// MARK: - Step 1: Welcome

struct WelcomePrivacyView: View {
    let onContinue: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to FindMyFlipper")
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(theme.textPrimary)

            ZStack {
                Circle()
                    .fill(theme.primaryOrange.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white, theme.primaryOrange)
            }
            .padding(.vertical, 8)

            VStack(spacing: 8) {
                Text("Track your Flipper Zero using Find My network reports.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                Text("Your data stays local and secure.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()

            PrimaryButton("Continue", icon: "") { onContinue() }
                .frame(width: 200)
        }
        .padding(32)
    }
}

// MARK: - Step 2: Import Keys

struct ImportKeysView: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    @State private var isImporting = false
    @State private var importedRecord: FindMyKeyRecord?
    @State private var errorMessage: String?
    @State private var folderMessage: String?
    @State private var showFilePicker = false
    @State private var flipperConnected = FlipperSDCardService.isFlipperConnected
    @State private var isPreparingFlipper = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Import .keys File")
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(theme.textPrimary)

            ZStack {
                Circle()
                    .fill(theme.primaryOrange.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "key.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(theme.primaryOrange)
            }
            .padding(.vertical, 8)

            Text("Choose the FindMyFlipper .keys file loaded on your own Flipper. The private key is stored in macOS Keychain.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Image(systemName: flipperConnected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(flipperConnected ? theme.successGreen : theme.textSecondary)
                Text(flipperConnected
                    ? "Flipper \(FlipperSDCardService.connectedDeviceName ?? "Zero") connected by USB"
                    : "Connect Flipper by USB to copy keys directly to its SD card")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .onAppear { flipperConnected = FlipperSDCardService.isFlipperConnected }

            HStack(spacing: 14) {
                FlipperZeroArtwork()
                    .frame(width: 104, height: 104)
                    .padding(8)
                    .background(theme.softOrangeSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Plug in your Flipper Zero")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.textPrimary)
                    Text("The app creates the Flipper folder and copies imported or generated keys to its microSD card over USB. Keep qFlipper closed while transferring.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        SecondaryButton(flipperConnected ? "Prepare Folder" : "Connect USB", icon: "cable.connector") {
                            prepareFlipperFolder()
                        }
                        .disabled(isPreparingFlipper)
                    }
                    Text(FlipperSDCardService.destinationDirectory)
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(12)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.cardBorder, lineWidth: 1)
            )

            if let importedRecord {
                VStack(spacing: 8) {
                    Label("Valid .keys file detected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.successGreen)
                        .font(.subheadline).fontWeight(.semibold)
                    Text("All required data was found in the file.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    Text(importedRecord.generatedFindMyMac)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                }
                .multilineTextAlignment(.center)
            }

            if let folderMessage = folderMessage {
                Text(folderMessage)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            
            Spacer()

            if importedRecord != nil {
                PrimaryButton("Continue", icon: "") { onContinue() }
                    .frame(width: 200)
            } else {
                VStack(spacing: 10) {
                    PrimaryButton("Choose .keys File", icon: "folder", isLoading: isImporting) {
                        showFilePicker = true
                    }
                    .frame(width: 220)

                    SecondaryButton("Generate New Keys", icon: "wand.and.stars") {
                        generateKeysInApp()
                    }
                    .frame(width: 220)
                    .disabled(isImporting)
                    .opacity(isImporting ? 0.5 : 1)
                }
            }
        }
        .padding(32)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                importKeys(url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func generateKeysInApp() {
        isImporting = true
        errorMessage = nil
        folderMessage = nil
        Task {
            do {
                await appState.backendManager.startBackend()
                let response = try await appState.backendClient.generateKeys()
                guard response.ok, let rawContent = response.rawContent else {
                    throw KeysParseError.missingRequiredField(response.error ?? "Failed to generate keys.")
                }

                let keysFilename = "findmyflipper-\(UUID().uuidString.prefix(8)).keys"
                let importFile = try writeGeneratedKeysToTemporaryFile(rawContent, filename: keysFilename)
                defer { try? FileManager.default.removeItem(at: importFile.deletingLastPathComponent()) }

                var sdCardMessage: String? = nil
                if FlipperSDCardService.isFlipperConnected {
                    do {
                        let destination = try await FlipperSDCardService.writeKeysToFlipperSD(
                            rawContent: rawContent,
                            filename: keysFilename
                        )
                        sdCardMessage = "Copied to your Flipper at \(destination)."
                    } catch {
                        throw error
                    }
                }

                let keyImportService = KeyImportService(keychain: appState.keychainService, profileStore: appState.profileStore)
                let record = try await keyImportService.importKeysFile(url: importFile, displayName: "My Flipper")
                try createOrRelinkActiveProfile(for: record)

                await MainActor.run {
                    importedRecord = record
                    folderMessage = sdCardMessage ?? "Keys generated and secured in Keychain. Connect your Flipper to copy them to its SD card."
                    isImporting = false
                    onContinue()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }

    private func importKeys(_ url: URL) {
        isImporting = true
        errorMessage = nil
        folderMessage = nil
        Task {
            do {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let rawContent = try String(contentsOf: url, encoding: .utf8)
                if FlipperSDCardService.isFlipperConnected {
                    _ = try await FlipperSDCardService.writeKeysToFlipperSD(
                        rawContent: rawContent,
                        filename: url.lastPathComponent
                    )
                }

                let keyImportService = KeyImportService(keychain: appState.keychainService, profileStore: appState.profileStore)
                let record = try await keyImportService.importKeysFile(url: url, displayName: "My Flipper")
                try createOrRelinkActiveProfile(for: record)

                await MainActor.run {
                    importedRecord = record
                    isImporting = false
                    onContinue()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }

    private func prepareFlipperFolder() {
        isPreparingFlipper = true
        errorMessage = nil
        folderMessage = "Connecting to your Flipper..."
        Task {
            do {
                let destination = try await FlipperSDCardService.prepareImportFolder()
                await MainActor.run {
                    flipperConnected = true
                    folderMessage = "Flipper folder ready at \(destination)."
                    isPreparingFlipper = false
                }
            } catch {
                await MainActor.run {
                    flipperConnected = FlipperSDCardService.isFlipperConnected
                    folderMessage = nil
                    errorMessage = error.localizedDescription
                    isPreparingFlipper = false
                }
            }
        }
    }

    private func writeGeneratedKeysToTemporaryFile(_ rawContent: String, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindMyFlipper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(filename)
        try rawContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    @MainActor
    private func createOrRelinkActiveProfile(for record: FindMyKeyRecord) throws {
        if appState.profileStore.activeProfile() != nil {
            try appState.profileStore.relinkActiveProfile(to: record)
        } else {
            let profile = FlipperProfile(
                id: UUID(),
                displayName: record.displayName.isEmpty ? "My Flipper" : record.displayName,
                createdAt: Date(),
                updatedAt: Date(),
                findMyKeyID: record.id,
                bleDeviceID: nil,
                generatedFindMyMac: record.generatedFindMyMac,
                payloadPreview: String(record.payload.prefix(64)),
                hashedAdvKeyPreview: String(record.hashedAdvKeyBase64.prefix(12)),
                lastReport: nil,
                lastBLEConnection: nil,
                batteryLevel: nil,
                isBLEConnected: false,
                autoReconnect: true,
                refreshInterval: .fifteenMin,
                isActive: true
            )
            try appState.profileStore.saveProfile(profile)
        }
    }
}

// MARK: - Step 3: Apple Access

struct AppleAccessView: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    var showsCancelButton = false
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var appleID = ""
    @State private var password = ""
    @State private var twoFactorCode = ""
    @State private var secondFactor = "trusted_device"
    @State private var needsTwoFactorCode = false
    @State private var existingAccessAccount: String?
    @State private var isCheckingExistingAccess = true
    @FocusState private var focusedAuthField: AuthField?

    private enum AuthField: Hashable {
        case appleID
        case password
        case code
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Connect Apple Access")
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(theme.textPrimary)

            Image(systemName: "apple.logo")
                .font(.system(size: 52))
                .foregroundStyle(theme.textSecondary)
                .padding(.vertical, 8)

            Text("Sign in to allow FindMyFlipper to request Find My location reports for your key.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Text("FindMyFlipper will start the local anisette service. If Docker is missing, it can install OrbStack with Homebrew.")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                TextField("Apple ID", text: $appleID)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .focused($focusedAuthField, equals: .appleID)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .focused($focusedAuthField, equals: .password)
                Picker("2FA", selection: $secondFactor) {
                    Text("Trusted Device").tag("trusted_device")
                    Text("SMS").tag("sms")
                }
                .pickerStyle(.segmented)

                if needsTwoFactorCode {
                    TextField("Two-factor code", text: $twoFactorCode)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.oneTimeCode)
                        .focused($focusedAuthField, equals: .code)
                    Text("Keep this window open. Enter the latest code Apple sent, then verify.")
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 340)

            if let existingAccessAccount, !needsTwoFactorCode {
                Label("Apple access is already connected for \(existingAccessAccount).", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(theme.successGreen)
                    .multilineTextAlignment(.center)
            }

            if let statusMessage = statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            
            Spacer()

            if existingAccessAccount != nil && !needsTwoFactorCode {
                SecondaryButton("Continue with Existing Access", icon: "arrow.right.circle") {
                    onContinue()
                }
                .frame(width: 240)
            }

            PrimaryButton(
                needsTwoFactorCode ? "Verify Code" : (existingAccessAccount == nil ? "Connect with Apple" : "Sign In Again"),
                icon: "shield.fill",
                isLoading: isConnecting || isCheckingExistingAccess
            ) {
                connectAppleAccess()
            }
            .frame(width: 240)
            .disabled(needsTwoFactorCode && twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity((needsTwoFactorCode && twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.55 : 1)
        }
        .padding(32)
        .task { await checkExistingAccess() }
        .overlay(alignment: .topTrailing) {
            if showsCancelButton {
                Button(action: onBack) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Close Apple access")
                .padding(16)
            }
        }
    }

    private func connectAppleAccess() {
        let trimmedAppleID = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if needsTwoFactorCode && trimmedCode.isEmpty {
            errorMessage = "Enter the two-factor code Apple sent to finish sign-in."
            focusedAuthField = .code
            return
        }

        if !needsTwoFactorCode && (trimmedAppleID.isEmpty || password.isEmpty) {
            errorMessage = "Enter your Apple ID and password to connect Apple access."
            focusedAuthField = trimmedAppleID.isEmpty ? .appleID : .password
            return
        }

        isConnecting = true
        errorMessage = nil
        statusMessage = needsTwoFactorCode ? "Verifying Apple two-factor code..." : "Starting local backend..."
        Task {
            do {
                await appState.backendManager.startBackend()

                await MainActor.run {
                    statusMessage = "Preparing local Apple access service..."
                }

                let anisetteResponse = try await appState.backendClient.startAnisette(installIfMissing: true)
                if !anisetteResponse.ok {
                    await MainActor.run {
                        isConnecting = false
                        statusMessage = nil
                        errorMessage = [
                            anisetteResponse.error,
                            anisetteResponse.detail
                        ]
                        .compactMap { $0 }
                        .joined(separator: " ")
                        if errorMessage?.isEmpty != false {
                            errorMessage = "Failed to start the local anisette service."
                        }
                    }
                    return
                }

                await MainActor.run {
                    statusMessage = anisetteResponse.message ?? "Connecting Apple access..."
                }

                let usernameForRequest = trimmedAppleID.isEmpty && needsTwoFactorCode ? nil : trimmedAppleID
                let passwordForRequest = password.isEmpty && needsTwoFactorCode ? nil : password
                let codeForRequest = trimmedCode.isEmpty ? nil : trimmedCode

                let authResponse = try await appState.backendClient.connectAuth(
                    username: usernameForRequest,
                    password: passwordForRequest,
                    secondFactor: secondFactor,
                    code: codeForRequest
                )
                guard authResponse.ok else {
                    await MainActor.run {
                        isConnecting = false
                        if authResponse.requires2FA == true {
                            needsTwoFactorCode = true
                            statusMessage = authResponse.error ?? "Enter the Apple two-factor code to finish sign-in."
                            errorMessage = nil
                            focusedAuthField = .code
                        } else {
                            statusMessage = nil
                            errorMessage = authResponse.error ?? "Apple access connection failed."
                        }
                    }
                    return
                }

                await MainActor.run {
                    isConnecting = false
                    statusMessage = nil
                    needsTwoFactorCode = false
                    existingAccessAccount = authResponse.accountIdentifier
                    onContinue()
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    statusMessage = nil
                    errorMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func checkExistingAccess() async {
        await appState.backendManager.startBackend()
        do {
            let status = try await appState.backendClient.authStatus()
            await MainActor.run {
                existingAccessAccount = status.connected ? status.accountIdentifier : nil
                isCheckingExistingAccess = false
            }
        } catch {
            await MainActor.run { isCheckingExistingAccess = false }
        }
    }
}

// MARK: - Step 4: Choose Flipper

struct ChooseFlipperBLEView: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    @State private var selectedDeviceID: UUID?
    @State private var hasStartedScan = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Your Flipper")
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(theme.textPrimary)

            Text("Start scanning when your Flipper is nearby. macOS will ask for Bluetooth access only when the scan starts.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)

            if !hasStartedScan {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 34))
                        .foregroundStyle(theme.primaryOrange)
                    Text("If the macOS Bluetooth permission window is already stuck, quit and reopen FindMyFlipper, then start the scan from here.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(height: 140)
            } else {
                deviceList
                    .frame(height: 140)
            }

            HStack(spacing: 10) {
                PrimaryButton(hasStartedScan ? "Scan Again" : "Start Bluetooth Scan", icon: "dot.radiowaves.left.and.right") {
                    hasStartedScan = true
                    appState.bleManager.startScan()
                }
                .frame(width: hasStartedScan ? 150 : 210)

                SecondaryButton("Skip for Now", icon: "arrow.right") {
                    appState.bleManager.stopScan()
                    onContinue()
                }
                .frame(width: 140)
            }
        }
        .padding(32)
        .onDisappear {
            if hasStartedScan {
                appState.bleManager.stopScan()
            }
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch appState.bleManager.scanState {
                case .error(let message):
                    VStack(spacing: 10) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(theme.errorRed)
                            .multilineTextAlignment(.center)
                        SecondaryButton("Open Bluetooth Settings", icon: "gear") {
                            openBluetoothSettings()
                        }
                    }
                    .padding(.top, 16)
                default:
                    if appState.bleManager.discoveredDevices.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(appState.bleManager.scanState == .scanning ? "Scanning nearby devices..." : "No devices found yet.")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(.top, 20)
                    } else {
                        ForEach(appState.bleManager.discoveredDevices) { device in
                            HStack(spacing: 10) {
                                Image(systemName: selectedDeviceID == device.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(selectedDeviceID == device.id ? theme.primaryOrange : theme.textSecondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(theme.textPrimary)
                                    Text(device.peripheralIdentifier.uuidString.prefix(8) + "...")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(theme.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(device.lastRSSI) dBm")
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                    Text(device.score.label)
                                        .font(.caption2)
                                        .foregroundStyle(device.score.badgeColor(theme))
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(selectedDeviceID == device.id ? theme.primaryOrange.opacity(0.1) : Color.clear)
                            .onTapGesture {
                                selectedDeviceID = device.id
                                appState.bleManager.selectDevice(device)
                                onContinue()
                            }
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension BLEDeviceScore {
    var label: String {
        switch self {
        case .recommended: return "Recommended"
        case .possibleFlipper: return "Possible"
        case .unknown: return "Unknown"
        case .weak: return "Weak"
        }
    }

    func badgeColor(_ theme: ThemeColors) -> Color {
        switch self {
        case .recommended: return theme.successGreen
        case .possibleFlipper: return theme.primaryOrange
        case .unknown: return theme.textSecondary
        case .weak: return theme.warningAmber
        }
    }
}

private struct FlipperZeroArtwork: View {
    @Environment(\.appTheme) private var theme
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
                    .foregroundStyle(theme.primaryOrange)
            }
        }
        .task {
            guard image == nil else { return }
            image = await FlipperProductImageLoader.load()
        }
    }
}

// MARK: - Step 5: Test Setup

struct TestSetupView: View {
    let onFinish: () -> Void
    let onBack: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    @State private var results: [DiagnosticResult] = []

    private var allPass: Bool { results.allSatisfy { $0.state == .pass } }
    private var canFinish: Bool { !results.isEmpty && results.allSatisfy { $0.state != .fail } }

    var body: some View {
        VStack(spacing: 20) {
            Text("Test Setup")
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(theme.textPrimary)

            VStack(spacing: 12) {
                if results.isEmpty {
                    ProgressView().padding(.vertical, 20)
                } else {
                    ForEach(results) { result in
                        HStack {
                            Image(systemName: result.state.iconName)
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundStyle(result.state.displayColor(theme))
                            Text(result.title)
                                .font(.subheadline).foregroundStyle(theme.textSecondary)
                            Spacer()
                            Text(result.state.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(result.state.displayColor(theme))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Spacer()

            if allPass && !results.isEmpty {
                Text("All tests passed!")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(theme.successGreen)
            } else if canFinish {
                Text("Setup can continue. You can link Bluetooth later from the Flipper page.")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(theme.warningAmber)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton("Finish Setup", icon: "") {
                onFinish()
            }
            .frame(width: 200)
            .disabled(!canFinish)
            .opacity(canFinish ? 1.0 : 0.5)
        }
        .padding(32)
        .onAppear {
            Task {
                let r = await appState.diagnosticsService.runAll()
                await MainActor.run { results = r }
            }
        }
    }
}

private extension DiagnosticState {
    var iconName: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        case .running: return "clock.fill"
        case .pending: return "circle"
        }
    }

    var label: String {
        switch self {
        case .pass: return "Passed"
        case .warning: return "Warning"
        case .fail: return "Failed"
        case .running: return "Running"
        case .pending: return "Pending"
        }
    }

    func displayColor(_ theme: ThemeColors) -> Color {
        switch self {
        case .pass: return theme.successGreen
        case .warning: return theme.warningAmber
        case .fail: return theme.errorRed
        case .running: return theme.primaryOrange
        case .pending: return theme.textSecondary
        }
    }
}
