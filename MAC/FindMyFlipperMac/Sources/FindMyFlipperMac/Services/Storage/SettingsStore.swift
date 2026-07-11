import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let fileURL: URL

    init(containerURL: URL? = nil) {
        let base = containerURL ?? Self.defaultContainerURL()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            settings = AppSettings()
        }
    }

    func update(_ new: AppSettings) {
        settings = new
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func defaultContainerURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FindMyFlipperMac")
    }
}
