import SwiftUI
import MapKit

// MARK: - ReportsView

struct ReportsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    @State private var selectedFilter: ReportFilter = .all
    @State private var selectedReport: LocationReport?
    @State private var searchText = ""

    private var filterOptions: [(String, ReportFilter)] = [
        ("Today", .today),
        ("24 Hours", .last24Hours),
        ("7 Days", .last7Days),
        ("All", .all),
        ("High Accuracy", .highAccuracy)
    ]

    private var displayedReports: [LocationReport] {
        guard let profileID = appState.activeProfile?.id else { return [] }
        let reports = appState.reportsStore.reports(forProfile: profileID, filter: selectedFilter)
        if searchText.isEmpty { return reports }
        return reports.filter {
            $0.isoDateTime.localizedCaseInsensitiveContains(searchText) ||
            appState.geocodingService.locationName(for: $0).localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var groupedReports: [(String, [LocationReport])] {
        let calendar = Calendar.current
        var dict: [String: [LocationReport]] = [:]
        for report in displayedReports {
            let date = Date(timeIntervalSince1970: report.timestamp)
            let key: String
            if calendar.isDateInToday(date) {
                key = "Today"
            } else if calendar.isDateInYesterday(date) {
                key = "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                key = formatter.string(from: date)
            }
            dict[key, default: []].append(report)
        }
        
        let sortedKeys = dict.keys.sorted {
            if $0 == "Today" { return true }
            if $1 == "Today" { return false }
            if $0 == "Yesterday" { return true }
            if $1 == "Yesterday" { return false }
            return $0 > $1
        }
        return sortedKeys.map { ($0, dict[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("Reports")
                    .font(.headline).fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Menu {
                    ForEach(filterOptions, id: \.0) { label, filter in
                        Button(label) { selectedFilter = filter }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Filter")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.cardBackground)
                    .foregroundStyle(theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(theme.background)

            if displayedReports.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Reports",
                    subtitle: "No reports match the current filter. Try a different time range or refresh."
                )
                Spacer()
            } else {
                List(selection: $selectedReport) {
                    ForEach(groupedReports, id: \.0) { group in
                        Section {
                            ForEach(group.1) { report in
                                ReportRowView(report: report)
                                    .tag(report)
                                    .listRowBackground(
                                        selectedReport?.id == report.id
                                            ? theme.softOrangeSurface
                                            : theme.cardBackground
                                    )
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 4)
                            }
                        } header: {
                            Text(group.0)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(theme.textSecondary)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(theme.background)
                
                // Footer
                Text("\(displayedReports.count) reports total")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.vertical, 12)
            }
        }
        .background(theme.background)
        .searchable(text: $searchText, prompt: "Search reports…")
        .sheet(item: $selectedReport) { report in
            ReportDetailView(report: report)
                .environment(\.appTheme, theme)
                .frame(minWidth: 520, minHeight: 460)
                .presentationBackground(theme.background)
        }
    }
}

// MARK: - ReportRowView

private struct ReportRowView: View {
    let report: LocationReport
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: report.timestamp))
    }

    var body: some View {
        HStack(spacing: 16) {
            // Time
            Text(timeString)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .frame(width: 60, alignment: .leading)
            
            // Location Details
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.geocodingService.locationName(for: report))
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(theme.textPrimary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(report.confidence >= 70 ? theme.successGreen : theme.warningAmber)
                        .frame(width: 6, height: 6)
                    Text("Accuracy: \(report.confidence >= 70 ? "High" : "Medium")")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
}

// MARK: - ReportDetailView

struct ReportDetailView: View {
    let report: LocationReport
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Map snapshot
            Map(initialPosition: .region(MKCoordinateRegion(
                center: report.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Annotation("", coordinate: report.coordinate) {
                    PastLocationMarker()
                }
            }
            .mapStyle(mapStyle)
            .frame(height: 200)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Report Details", systemImage: "mappin.and.ellipse")
                                .font(.headline).foregroundStyle(theme.textPrimary)
                            Divider()
                            detailGrid
                        }
                    }
                    .padding(16)
                }
            }
            .background(theme.background)

            // Bottom bar
            HStack {
                Button("Open in Maps") {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: report.coordinate))
                    item.name = appState.activeProfile?.displayName ?? "Flipper"
                    item.openInMaps()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.primaryOrange)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(theme.primaryOrange)
            }
            .padding(16)
            .background(theme.cardBackground)
            .overlay(Divider().background(theme.cardBorder), alignment: .top)
        }
        .background(theme.background.ignoresSafeArea())
    }

    private var mapStyle: MapStyle {
        switch appState.settings.mapDisplayMode {
        case .standard:
            return .standard(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        case .imagery:
            return .imagery(elevation: .realistic)
        }
    }

    private var detailGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            detailCell("Latitude", value: String(format: "%.7f", report.lat))
            detailCell("Longitude", value: String(format: "%.7f", report.lon))
            detailCell("Confidence", value: "\(report.confidence)%")
            detailCell("Timestamp", value: report.isoDateTime)
            detailCell("Location", value: appState.geocodingService.locationName(for: report))
            detailCell("Source", value: report.source)
        }
    }

    private func detailCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(theme.textSecondary)
            Text(value).font(.caption.monospaced()).foregroundStyle(theme.textPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 8))
    }
}
