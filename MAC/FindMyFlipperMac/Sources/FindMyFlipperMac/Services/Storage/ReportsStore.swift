import Foundation
import Combine

enum ReportFilter: Equatable {
    case all
    case today
    case last24Hours
    case last7Days
    case last30Days
    case live          // most recent only
    case highAccuracy  // confidence >= 70
    case hours(Int)    // last N hours
}

@MainActor
final class ReportsStore: ObservableObject {
    static let maxReportsPerProfile = 10_000

    @Published var reportsByProfile: [UUID: [LocationReport]] = [:]

    private let storageURL: URL

    init(containerURL: URL? = nil) {
        let base = containerURL ?? Self.defaultContainerURL()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        storageURL = base.appendingPathComponent("reports")
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    // MARK: - Insert

    /// Insert reports for a profile, deduplicating by report.id. Auto-prunes to maxReportsPerProfile.
    func insert(_ newReports: [LocationReport], forProfile profileID: UUID) throws {
        var existing = load(forProfile: profileID)
        let existingIDs = Set(existing.map { $0.id })
        // Deduplicate within the incoming batch first, then against existing records
        var seenInBatch = Set<String>()
        let toAdd = newReports.filter { report in
            guard !existingIDs.contains(report.id), seenInBatch.insert(report.id).inserted else {
                return false
            }
            return true
        }
        existing.append(contentsOf: toAdd)
        // Sort by timestamp descending
        existing.sort { $0.timestamp > $1.timestamp }
        // Prune to max capacity
        if existing.count > Self.maxReportsPerProfile {
            existing = Array(existing.prefix(Self.maxReportsPerProfile))
        }
        try persist(existing, forProfile: profileID)
        reportsByProfile[profileID] = existing
    }

    // MARK: - Query

    func reports(forProfile profileID: UUID, filter: ReportFilter = .all) -> [LocationReport] {
        let all = reportsByProfile[profileID] ?? load(forProfile: profileID)
        return apply(filter: filter, to: all)
    }

    func latestReport(forProfile profileID: UUID) -> LocationReport? {
        reports(forProfile: profileID).first
    }

    func totalCount(forProfile profileID: UUID) -> Int {
        reports(forProfile: profileID).count
    }

    // MARK: - Delete

    func clearReports(forProfile profileID: UUID) throws {
        reportsByProfile[profileID] = []
        let file = reportFile(forProfile: profileID)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Private helpers

    private func apply(filter: ReportFilter, to reports: [LocationReport]) -> [LocationReport] {
        let now = Date().timeIntervalSince1970
        switch filter {
        case .all:
            return reports
        case .live:
            return Array(reports.prefix(1))
        case .today:
            let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
            return reports.filter { $0.timestamp >= startOfDay }
        case .last24Hours:
            return reports.filter { $0.timestamp >= now - 86400 }
        case .last7Days:
            return reports.filter { $0.timestamp >= now - 7 * 86400 }
        case .last30Days:
            return reports.filter { $0.timestamp >= now - 30 * 86400 }
        case .highAccuracy:
            return reports.filter { $0.confidence >= 70 }
        case .hours(let h):
            return reports.filter { $0.timestamp >= now - Double(h) * 3600 }
        }
    }

    private func load(forProfile profileID: UUID) -> [LocationReport] {
        let file = reportFile(forProfile: profileID)
        guard let data = try? Data(contentsOf: file),
              let reports = try? JSONDecoder().decode([LocationReport].self, from: data) else {
            return []
        }
        reportsByProfile[profileID] = reports
        return reports
    }

    private func persist(_ reports: [LocationReport], forProfile profileID: UUID) throws {
        let data = try JSONEncoder().encode(reports)
        try data.write(to: reportFile(forProfile: profileID), options: .atomic)
    }

    private func reportFile(forProfile profileID: UUID) -> URL {
        storageURL.appendingPathComponent("\(profileID.uuidString).json")
    }

    private static func defaultContainerURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FindMyFlipperMac")
    }
}
