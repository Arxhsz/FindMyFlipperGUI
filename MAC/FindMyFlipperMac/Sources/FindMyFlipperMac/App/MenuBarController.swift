import SwiftUI

struct MenuBarSummary {
    var statusLabel: String
    var batteryLevel: Int?
    var lastReportAge: String?
    var isConnected: Bool
}

@MainActor
final class MenuBarController: ObservableObject {
    @Published var statusSummary: MenuBarSummary = MenuBarSummary(
        statusLabel: "No profile configured",
        batteryLevel: nil,
        lastReportAge: nil,
        isConnected: false
    )

    func updateStatus(from profile: FlipperProfile?) {
        guard let profile else {
            statusSummary = MenuBarSummary(
                statusLabel: "No profile configured",
                batteryLevel: nil,
                lastReportAge: nil,
                isConnected: false
            )
            return
        }
        statusSummary = MenuBarSummary(
            statusLabel: profile.isBLEConnected ? "Connected" : "Disconnected",
            batteryLevel: profile.batteryLevel,
            lastReportAge: profile.lastReport.map { formatAge($0.timestamp) },
            isConnected: profile.isBLEConnected
        )
    }
    private func formatAge(_ timestamp: TimeInterval) -> String {
        let age = Date().timeIntervalSince1970 - timestamp
        if age < 60 { return "Just now" }
        if age < 3600 { return "\(Int(age / 60)) min ago" }
        return "\(Int(age / 3600))h ago"
    }
}
