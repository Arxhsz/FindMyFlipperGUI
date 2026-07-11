import SwiftUI

// MARK: - ProfilesView

struct ProfilesView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    @State private var showAddProfile = false
    @State private var profileToRename: FlipperProfile?
    @State private var newName = ""
    @State private var profileToDelete: FlipperProfile?
    @State private var operationError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Profiles").font(.title3).fontWeight(.bold).foregroundStyle(theme.textPrimary)
                Spacer()
                PrimaryButton("Add Profile", icon: "plus") { showAddProfile = true }
            }
            .padding(16)
            .background(theme.cardBackground)
            .overlay(Divider(), alignment: .bottom)

            if appState.profiles.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "person.circle",
                    title: "No Profiles",
                    subtitle: "Add a profile to start tracking your Flipper Zero.",
                    actionTitle: "Add Profile"
                ) { showAddProfile = true }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(appState.profiles) { profile in
                            ProfileCard(
                                profile: profile,
                                latestReport: appState.reportsStore.latestReport(forProfile: profile.id),
                                reportCount: appState.reportsStore.reports(forProfile: profile.id).count,
                                onSetActive: {
                                    do {
                                        try appState.profileStore.setActive(profileID: profile.id)
                                    } catch {
                                        operationError = error.localizedDescription
                                    }
                                },
                                onRename: {
                                    profileToRename = profile
                                    newName = profile.displayName
                                },
                                onDelete: {
                                    profileToDelete = profile
                                }
                            )
                        }
                    }
                    .padding(24)
                }
                .background(theme.background)
            }
        }
        .background(theme.background)
        .sheet(isPresented: $showAddProfile) {
            AddProfileView()
                .frame(minWidth: 480, minHeight: 420)
        }
        .alert("Rename Profile", isPresented: Binding(
            get: { profileToRename != nil },
            set: { if !$0 { profileToRename = nil } }
        )) {
            TextField("Display Name", text: $newName)
            Button("Save") {
                if var p = profileToRename {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        operationError = "Profile name cannot be empty."
                        profileToRename = nil
                        return
                    }
                    p.displayName = trimmed
                    do {
                        try appState.profileStore.updateProfile(p)
                    } catch {
                        operationError = error.localizedDescription
                    }
                }
                profileToRename = nil
            }
            Button("Cancel", role: .cancel) { profileToRename = nil }
        }
        .alert("Delete Profile?", isPresented: Binding(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let p = profileToDelete {
                    deleteProfile(p)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: {
            Text("This removes the profile, its saved reports, and key material that is not used by another profile.")
        }
        .alert("Profile Operation Failed", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "The profile could not be updated.")
        }
    }

    private func deleteProfile(_ profile: FlipperProfile) {
        do {
            try appState.reportsStore.clearReports(forProfile: profile.id)
            try appState.profileStore.deleteProfile(id: profile.id)
            let unreferenced = try appState.profileStore.removeUnreferencedKeyRecords()
            for record in unreferenced {
                do {
                    try appState.keychainService.deletePrivateKey(forID: record.keychainKeyID)
                } catch KeychainError.itemNotFound {
                    continue
                }
            }
        } catch {
            operationError = error.localizedDescription
        }
    }
}

// MARK: - ProfileCard

private struct ProfileCard: View {
    let profile: FlipperProfile
    let latestReport: LocationReport?
    let reportCount: Int
    let onSetActive: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(.title3).fontWeight(.bold)
                            .foregroundStyle(theme.textPrimary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            if let report = latestReport {
                                Text("Last seen \(relativeTime(report.timestamp))")
                                    .font(.subheadline).foregroundStyle(theme.textSecondary)
                            } else {
                                Text("No reports yet").font(.subheadline).foregroundStyle(theme.textSecondary)
                            }
                            Text("\(reportCount) \(reportCount == 1 ? "report" : "reports")")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)

                            Text("Find My MAC \(profile.generatedFindMyMac)")
                                .font(.caption.monospaced())
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            if let bleID = profile.bleDeviceID {
                                Text("BLE \(bleID.uuidString)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.62)
                            }
                            
                            if let battery = profile.batteryLevel {
                                HStack(spacing: 6) {
                                    Image(systemName: BatteryDisplay.symbolName(for: battery))
                                        .font(.caption)
                                        .foregroundStyle(BatteryDisplay.color(for: battery, theme: theme))
                                    Text("Battery").font(.subheadline).foregroundStyle(theme.textSecondary)
                                    Text("\(battery)%")
                                        .font(.subheadline)
                                        .foregroundStyle(BatteryDisplay.color(for: battery, theme: theme))
                                }
                            }
                        }
                    }
                    Spacer()
                    
                    HStack(spacing: 12) {
                        if profile.isActive {
                            Text("Active")
                                .font(.caption).fontWeight(.semibold)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(theme.primaryOrange.opacity(0.15))
                                .foregroundStyle(theme.primaryOrange)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(theme.primaryOrange.opacity(0.22), lineWidth: 1))
                        }
                        
                        Menu {
                            if !profile.isActive {
                                Button("Set Active", action: onSetActive)
                            }
                            Button("Rename", action: onRename)
                            Button("Delete", role: .destructive, action: onDelete)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(theme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(theme.cardBorder.opacity(0.95), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
        }
    }

    private func relativeTime(_ ts: TimeInterval) -> String {
        let age = Date().timeIntervalSince1970 - ts
        if age < 60 { return "Just now" }
        if age < 3600 { return "\(Int(age/60))m ago" }
        return "\(Int(age/3600))h ago"
    }
}

// MARK: - AddProfileView

struct AddProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var displayName = ""
    @State private var showFilePicker = false
    @State private var importedRecord: FindMyKeyRecord?
    @State private var importError: String?
    @State private var isImporting = false
    @State private var didCommitProfile = false

    private var isValid: Bool { !displayName.isEmpty && importedRecord != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Profile").font(.title3).fontWeight(.bold).foregroundStyle(theme.textPrimary)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plain)
            }
            .padding(16)
            .background(theme.cardBackground)
            .overlay(Divider(), alignment: .bottom)

            ScrollView {
                VStack(spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Profile Name", systemImage: "person.circle")
                                .font(.headline).foregroundStyle(theme.textPrimary)
                            TextField("e.g. My Flipper", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Keys File", systemImage: "key.fill")
                                .font(.headline).foregroundStyle(theme.textPrimary)
                            if let record = importedRecord {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.successGreen)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.displayName).font(.subheadline).foregroundStyle(theme.textPrimary)
                                        Text(record.generatedFindMyMac).font(.caption.monospaced()).foregroundStyle(theme.textSecondary)
                                    }
                                }
                            } else {
                                SecondaryButton("Choose .keys File", icon: "folder") { showFilePicker = true }
                                if let err = importError {
                                    Text(err).font(.caption).foregroundStyle(theme.errorRed)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(theme.background)

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                PrimaryButton("Add Profile", icon: "plus", isLoading: isImporting) {
                    addProfile()
                }
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.5)
            }
            .padding(16)
            .background(.regularMaterial)
            .overlay(Divider(), alignment: .top)
        }
        .background(theme.background)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): importKeys(url: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .onDisappear { cleanupUncommittedKeyIfNeeded() }
    }

    private func importKeys(url: URL) {
        isImporting = true
        importError = nil
        Task {
            do {
                let service = KeyImportService(keychain: appState.keychainService, profileStore: appState.profileStore)
                let record = try await service.importKeysFile(url: url, displayName: displayName.isEmpty ? nil : displayName)
                await MainActor.run {
                    if let previous = importedRecord {
                        try? appState.profileStore.deleteKeyRecord(id: previous.id)
                        try? appState.keychainService.deletePrivateKey(forID: previous.keychainKeyID)
                    }
                    importedRecord = record
                    isImporting = false
                }
            } catch {
                await MainActor.run { importError = error.localizedDescription; isImporting = false }
            }
        }
    }

    private func addProfile() {
        guard let record = importedRecord else { return }
        let profile = FlipperProfile(
            id: UUID(),
            displayName: displayName,
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
            isActive: appState.profiles.isEmpty
        )
        do {
            try appState.profileStore.saveProfile(profile)
            didCommitProfile = true
            dismiss()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func cleanupUncommittedKeyIfNeeded() {
        guard !didCommitProfile, let record = importedRecord else { return }
        try? appState.profileStore.deleteKeyRecord(id: record.id)
        try? appState.keychainService.deletePrivateKey(forID: record.keychainKeyID)
    }
}
