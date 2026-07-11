import Foundation
import UserNotifications

// MARK: - NotificationService
// Task 26: UserNotifications for new reports, Flipper nearby, and low battery.

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    // MARK: - Permission

    /// Request notification permission once at first launch.
    func requestAuthorizationIfNeeded() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Triggers

    func notifyNewReport(profileName: String, location: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        send(
            id: "new_report_\(UUID().uuidString)",
            title: "New Location Report",
            body: "\(profileName) was just seen near \(location).",
            threadIdentifier: "reports"
        )
    }

    func notifyFlipperNearby(profileName: String) {
        send(
            id: "flipper-nearby",
            title: "📡 Flipper Nearby",
            body: "\(profileName) is within Bluetooth range."
        )
    }

    func notifyLowBattery(profileName: String, level: Int) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        send(
            id: "battery_\(profileName)",
            title: "Low Battery",
            body: "\(profileName) is at \(level)%. Please charge it soon.",
            threadIdentifier: "battery"
        )
    }

    // MARK: - Private

    private func send(id: String, title: String, body: String, threadIdentifier: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = threadIdentifier ?? ""
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
