import AppKit
import Combine
import SwiftUI
import UserNotifications

@main
struct FindMyFlipperMacApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var router = AppRouter()
    @StateObject private var statusItemController = MenuBarStatusItemController()

    var body: some Scene {
        // Main window
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(router)
                .background(WindowChromeConfigurator())
                .onAppear {
                    statusItemController.configure(appState: appState, router: router)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            EmptyView()
        }
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

// MARK: - Menu Bar Status Item

@MainActor
final class MenuBarStatusItemController: ObservableObject {
    private var statusItem: NSStatusItem?
    private weak var appState: AppState?
    private weak var router: AppRouter?
    private var cancellables = Set<AnyCancellable>()

    func configure(appState: AppState, router: AppRouter) {
        self.appState = appState
        self.router = router

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = "FindMyFlipper"
            statusItem = item
        }

        bindIfNeeded(to: appState)
        refreshIcon()
        rebuildMenu()
    }

    private func bindIfNeeded(to appState: AppState) {
        guard cancellables.isEmpty else { return }

        appState.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        appState.$activeProfile
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let theme = appState?.settings.theme ?? .light
        button.image = Self.makeFlipperGlyphImage(color: Self.accentColor(for: theme))
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let appState, let router, let profile = appState.activeProfile {
            menu.addItem(Self.disabledItem(profile.displayName, isBold: true))
            menu.addItem(Self.disabledItem(appState.menuBarController.statusSummary.statusLabel))

            if let battery = profile.batteryLevel {
                menu.addItem(Self.disabledItem("Battery: \(battery)%"))
            }
            if let bleID = profile.bleDeviceID {
                menu.addItem(Self.disabledItem("Bluetooth ID: \(bleID.uuidString)", usesMonospacedDigit: true))
            }
            if let age = appState.menuBarController.statusSummary.lastReportAge {
                menu.addItem(Self.disabledItem("Last report: \(age)"))
            }

            menu.addItem(.separator())
            menu.addItem(Self.actionItem("Open Dashboard") {
                NSApp.activate(ignoringOtherApps: true)
                router.currentDestination = .dashboard
            })

            let playAlertItem = Self.actionItem("Play Alert") {
                appState.bleManager.playAlert()
            }
            playAlertItem.isEnabled = appState.bleManager.alertAvailable
            menu.addItem(playAlertItem)

            menu.addItem(Self.actionItem("Refresh Reports") {
                Task { await appState.refreshService.triggerManualRefresh() }
            })

            menu.addItem(.separator())
            menu.addItem(Self.actionItem("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                router.currentDestination = .settings
            })
        } else {
            menu.addItem(Self.disabledItem("No profile configured"))
            menu.addItem(Self.actionItem("Open FindMyFlipper") {
                NSApp.activate(ignoringOtherApps: true)
            })
            menu.addItem(.separator())
        }

        menu.addItem(Self.actionItem("Quit") {
            NSApp.terminate(nil)
        })

        statusItem?.menu = menu
    }

    private static func disabledItem(_ title: String, isBold: Bool = false, usesMonospacedDigit: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false

        let font: NSFont
        if isBold {
            font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        } else if usesMonospacedDigit {
            font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        } else {
            font = .systemFont(ofSize: NSFont.systemFontSize)
        }

        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }

    private static func actionItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        CallbackMenuItem(title: title, actionHandler: action)
    }

    private static func accentColor(for theme: ThemeOption) -> NSColor {
        switch theme {
        case .light, .system:
            return NSColor(hex: "#FF5A00")
        case .dark:
            return NSColor(hex: "#FF6A1A")
        case .sunset:
            return NSColor(hex: "#F97316")
        case .ocean:
            return NSColor(hex: "#0EA5E9")
        case .forest:
            return NSColor(hex: "#22C55E")
        case .purple:
            return NSColor(hex: "#A855F7")
        }
    }

    private static func makeFlipperGlyphImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 25, height: 18))
        image.lockFocus()
        defer { image.unlockFocus() }

        color.setStroke()
        color.setFill()

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 3.5, y: 9))
        body.line(to: NSPoint(x: 6.8, y: 14.5))
        body.line(to: NSPoint(x: 19.2, y: 14.5))
        body.line(to: NSPoint(x: 22.2, y: 9))
        body.line(to: NSPoint(x: 19.2, y: 3.5))
        body.line(to: NSPoint(x: 6.8, y: 3.5))
        body.close()
        body.lineWidth = 2.1
        body.lineJoinStyle = .round
        body.lineCapStyle = .round
        body.stroke()

        let screen = NSBezierPath(
            roundedRect: NSRect(x: 9.3, y: 7.2, width: 5.6, height: 3.6),
            xRadius: 0.8,
            yRadius: 0.8
        )
        screen.lineWidth = 1.45
        screen.stroke()

        NSBezierPath(ovalIn: NSRect(x: 16.8, y: 7.6, width: 2.9, height: 2.9)).fill()

        image.isTemplate = false
        return image
    }
}

private final class CallbackMenuItem: NSMenuItem {
    private let actionHandler: () -> Void

    init(title: String, actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        actionHandler()
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let red = CGFloat((int >> 16) & 0xFF) / 255
        let green = CGFloat((int >> 8) & 0xFF) / 255
        let blue = CGFloat(int & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
