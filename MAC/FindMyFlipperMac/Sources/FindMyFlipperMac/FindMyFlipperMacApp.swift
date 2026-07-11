import AppKit
import SwiftUI
import UserNotifications

@main
struct FindMyFlipperMacApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var router = AppRouter()
    @Environment(\.colorScheme) private var colorScheme

    var body: some Scene {
        // Main window
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(router)
                .background(WindowChromeConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Menu bar extra (task 22)
        MenuBarExtra("FindMyFlipper", image: "MenuBarFlipper") {
            MenuBarMenuContent()
                .environmentObject(appState)
                .environmentObject(router)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
    }
}

// MARK: - Menu Bar Menu Content

struct MenuBarMenuContent: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            if let profile = appState.activeProfile {
                // Status header
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName).font(.headline)
                    Text(appState.menuBarController.statusSummary.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let battery = profile.batteryLevel {
                        Label("Battery: \(battery)%", systemImage: BatteryDisplay.symbolName(for: battery))
                            .font(.caption)
                            .foregroundStyle(BatteryDisplay.color(for: battery, theme: menuTheme))
                    }
                    if let bleID = profile.bleDeviceID {
                        Text("Bluetooth ID: \(bleID.uuidString)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let age = appState.menuBarController.statusSummary.lastReportAge {
                        Text("Last report: \(age)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Button("Open Dashboard") {
                    NSApp.activate(ignoringOtherApps: true)
                    router.currentDestination = .dashboard
                }
                Button("Play Alert") {
                    appState.bleManager.playAlert()
                }
                .disabled(!appState.bleManager.alertAvailable)
                Button("Refresh Reports") {
                    Task { await appState.refreshService.triggerManualRefresh() }
                }
                Divider()
                Button("Settings") {
                    NSApp.activate(ignoringOtherApps: true)
                    router.currentDestination = .settings
                }
            } else {
                Text("No profile configured").foregroundStyle(.secondary)
                Button("Open FindMyFlipper") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
    }

    private var menuTheme: ThemeColors {
        ThemeColors.colors(for: appState.settings.theme)
    }
}
