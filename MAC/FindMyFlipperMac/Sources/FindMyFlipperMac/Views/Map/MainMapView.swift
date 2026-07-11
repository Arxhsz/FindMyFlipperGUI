import SwiftUI
import MapKit

// MARK: - MainMapView

struct MainMapView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    @State private var selectedFilter: TimeFilter = .live
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedReport: LocationReport?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var customStartDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var showingCustomTimeline = false
    @State private var isHoveringLiveMarker = false

    enum TimeFilter: String, CaseIterable {
        case live = "Live"
        case oneHour = "1H"
        case sixHour = "6H"
        case day = "24H"
        case week = "7D"
        case month = "30D"
        case custom = "Custom"

        var hours: Int? {
            switch self {
            case .live: return 1
            case .oneHour: return 1
            case .sixHour: return 6
            case .day: return 24
            case .week: return 168
            case .month: return 720
            case .custom: return nil
            }
        }
    }

    private var filteredReports: [LocationReport] {
        if selectedFilter == .custom {
            let lower = min(customStartDate.timeIntervalSince1970, customEndDate.timeIntervalSince1970)
            let upper = max(customStartDate.timeIntervalSince1970, customEndDate.timeIntervalSince1970)
            return appState.reports.filter { $0.timestamp >= lower && $0.timestamp <= upper }
        }
        guard let hours = selectedFilter.hours else { return appState.reports }
        let cutoff = Date().timeIntervalSince1970 - Double(hours * 3600)
        return appState.reports.filter { $0.timestamp >= cutoff }
    }

    private var latestReport: LocationReport? { filteredReports.first }
    private var sortedReportsOldestFirst: [LocationReport] {
        filteredReports.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        ZStack {
            // Background Map
            if appState.reports.isEmpty {
                NoReportsView()
            } else {
                Map(position: $cameraPosition) {
                    if selectedFilter != .live, sortedReportsOldestFirst.count > 1 {
                        MapPolyline(coordinates: sortedReportsOldestFirst.map(\.coordinate))
                            .stroke(theme.primaryOrange.opacity(0.78), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }

                    // Most recent report marker
                    if let latest = latestReport {
                        Annotation("", coordinate: latest.coordinate) {
                            Button {
                                selectedReport = selectedReport?.id == latest.id ? nil : latest
                            } label: {
                                FlipperMarkerView(
                                    isPulsing: true,
                                    iconStyle: appState.settings.flipperIconStyle,
                                    alertToken: appState.bleManager.alertAnimationToken
                                )
                                .frame(width: 56, height: 56)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringLiveMarker = hovering
                                if hovering {
                                    selectedReport = latest
                                } else if selectedReport?.id == latest.id {
                                    selectedReport = nil
                                }
                            }
                            .overlay(alignment: .top) {
                                if selectedReport?.id == latest.id {
                                    MapMarkerCallout(
                                        report: latest,
                                        profileName: appState.activeProfile?.displayName ?? "Flipper",
                                        batteryLevel: appState.activeProfile?.batteryLevel,
                                        locationName: appState.geocodingService.locationName(for: latest),
                                        iconStyle: appState.settings.flipperIconStyle
                                    )
                                    .offset(y: -132)
                                    .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
                                    .allowsHitTesting(false)
                                }
                            }
                            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: selectedReport?.id)
                            .id("live-\(latest.id)-\(appState.settings.flipperIconStyle.rawValue)-\(appState.bleManager.alertAnimationToken)")
                        }
                    }
                    // Historical annotations
                    if filteredReports.count <= Constants.mapClusteringThreshold {
                        ForEach(sortedReportsOldestFirst.filter { $0.id != latestReport?.id }) { report in
                            Annotation("", coordinate: report.coordinate) {
                                HistoricalReportDot(
                                    report: report,
                                    selectedFilter: selectedFilter
                                )
                            }
                        }
                    }
                }
                .mapStyle(mapStyle(for: appState.settings.mapDisplayMode))
                .ignoresSafeArea(edges: [.top, .bottom, .trailing])
                .onTapGesture {
                    selectedReport = nil
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                }

                // UI Overlay
                VStack {
                    // Floating Top Bar
                    HStack {
                        Spacer()
                        MapFloatingTopBar(latestReport: latestReport)
                            .padding(.top, 16)
                            .padding(.trailing, 16)
                    }
                    
                    Spacer()
                    
                    // Floating Bottom Controls
                    HStack(alignment: .bottom) {
                        // Time Pills
                        TimeFilterPills(
                            selectedFilter: $selectedFilter,
                            customStartDate: customStartDate,
                            customEndDate: customEndDate
                        ) {
                            showingCustomTimeline = true
                        }
                            .padding(.leading, 16)
                            .padding(.bottom, 16)
                        
                        Spacer()
                        
                        // Map Controls Right
                        VStack(alignment: .trailing, spacing: 12) {
                            MapControlsWidget(
                                cameraPosition: $cameraPosition,
                                visibleRegion: visibleRegion,
                                latestReport: latestReport,
                                mapDisplayMode: appState.settings.mapDisplayMode,
                                onToggleMapMode: toggleMapMode
                            )
                            
                            Button {
                                if let report = latestReport {
                                    let item = MKMapItem(placemark: MKPlacemark(coordinate: report.coordinate))
                                    item.name = appState.activeProfile?.displayName ?? "Flipper"
                                    item.openInMaps()
                                }
                            } label: {
                                HStack {
                                    Text("Open in Maps").font(.subheadline).fontWeight(.medium)
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(theme.cardBackground)
                                .foregroundStyle(theme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCustomTimeline) {
            CustomTimelineSheet(
                startDate: $customStartDate,
                endDate: $customEndDate,
                onApply: {
                    selectedFilter = .custom
                    showingCustomTimeline = false
                    focusReports(filteredReports)
                }
            )
            .environment(\.appTheme, theme)
            .frame(width: 420, height: 270)
        }
        .onChange(of: selectedFilter) { _, _ in
            focusReports(filteredReports)
        }
    }

    private func mapStyle(for mode: MapDisplayMode) -> MapStyle {
        switch mode {
        case .standard:
            return .standard(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        case .imagery:
            return .imagery(elevation: .realistic)
        }
    }

    private func toggleMapMode() {
        var settings = appState.settings
        settings.mapDisplayMode = settings.mapDisplayMode.next
        appState.settingsStore.update(settings)
    }

    private func focusReports(_ reports: [LocationReport]) {
        guard !reports.isEmpty else { return }
        selectedReport = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            if reports.count == 1, let report = reports.first {
                cameraPosition = .region(MKCoordinateRegion(
                    center: report.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            } else {
                cameraPosition = .region(Self.region(containing: reports.map(\.coordinate)))
            }
        }
    }

    static func region(containing coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let latDelta = max((maxLat - minLat) * 1.45, 0.01)
        let lonDelta = max((maxLon - minLon) * 1.45, 0.01)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: min(latDelta, 120), longitudeDelta: min(lonDelta, 120))
        )
    }
}

// MARK: - MapFloatingTopBar

private struct MapFloatingTopBar: View {
    let latestReport: LocationReport?
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.appTheme) private var theme
    @State private var profileSelectionError: String?

    var body: some View {
        HStack(spacing: 16) {
            // Left Pill: Profile selector + Connection Status
            HStack(spacing: 12) {
                Menu {
                    ForEach(appState.profiles) { profile in
                        Button(profile.displayName) {
                            do {
                                try appState.profileStore.setActive(profileID: profile.id)
                            } catch {
                                profileSelectionError = error.localizedDescription
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        FlipperGlyphIcon()
                            .foregroundStyle(theme.primaryOrange)
                            .frame(width: 16, height: 16)
                        Text(appState.activeProfile?.displayName ?? "No Profile")
                            .font(.subheadline).fontWeight(.medium).foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .frame(maxWidth: 96, alignment: .leading)
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                
                Divider().frame(height: 16)
                
                let isConnected = appState.activeProfile?.isBLEConnected == true
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? theme.successGreen : theme.textSecondary)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "Connected" : "Disconnected")
                        .font(.caption).fontWeight(.medium).foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(theme.cardBackground)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

            // Center Info: Last Seen
            if let report = latestReport {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Last seen \(relativeTime(report.timestamp))")
                            .font(.caption).foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        SmoothRefreshIcon(isSpinning: appState.refreshService.isRefreshing)
                            .font(.caption2)
                            .foregroundStyle(theme.primaryOrange)
                            .frame(width: 12, height: 12)
                    }
                    Text(appState.geocodingService.locationName(for: report))
                        .font(.caption).fontWeight(.medium).foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.cardBackground.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(theme.cardBorder.opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            }

            // Actions
            HStack(spacing: 8) {
                Button {
                    appState.bleManager.playAlert()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2.fill")
                        Text("Play Alert")
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .font(.subheadline).fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(theme.primaryOrange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Refresh Now", action: { Task { await appState.refreshService.triggerManualRefresh() } })
                    Button("Diagnostics", action: { router.currentDestination = .settings })
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(theme.cardBackground)
                        .foregroundStyle(theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.cardBorder.opacity(0.95), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .alert("Could Not Switch Profile", isPresented: Binding(
            get: { profileSelectionError != nil },
            set: { if !$0 { profileSelectionError = nil } }
        )) {
            Button("OK") { profileSelectionError = nil }
        } message: {
            Text(profileSelectionError ?? "The profile could not be activated.")
        }
    }

    private func relativeTime(_ ts: TimeInterval) -> String {
        let age = Date().timeIntervalSince1970 - ts
        if age < 60 { return "Just now" }
        if age < 3600 { return "\(Int(age/60)) min ago" }
        if age < 86400 { return "\(Int(age/3600)) hrs ago" }
        return "\(Int(age/86400)) days ago"
    }
}

private struct SmoothRefreshIcon: View {
    let isSpinning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isSpinning)) { context in
            Image(systemName: "arrow.triangle.2.circlepath")
                .rotationEffect(.degrees(rotationDegrees(at: context.date)))
        }
    }

    private func rotationDegrees(at date: Date) -> Double {
        guard isSpinning else { return 0 }
        let seconds = date.timeIntervalSinceReferenceDate
        return seconds.truncatingRemainder(dividingBy: 1.0) * 360
    }
}

// MARK: - TimeFilterPills

private struct TimeFilterPills: View {
    @Binding var selectedFilter: MainMapView.TimeFilter
    let customStartDate: Date
    let customEndDate: Date
    let onCustomTimeline: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainMapView.TimeFilter.allCases.filter { $0 != .custom }, id: \.self) { filter in
                Button(filter.rawValue) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedFilter = filter }
                }
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    selectedFilter == filter ? theme.primaryOrange : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(selectedFilter == filter ? .white : theme.textSecondary)
                .buttonStyle(.plain)
            }
            Divider().frame(height: 16)
            Button {
                onCustomTimeline()
            } label: {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(selectedFilter == .custom ? .white : theme.textSecondary)
                    .frame(width: 34, height: 30)
                    .background(
                        selectedFilter == .custom ? theme.primaryOrange : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

}

// MARK: - MapControlsWidget

private struct MapControlsWidget: View {
    @Binding var cameraPosition: MapCameraPosition
    let visibleRegion: MKCoordinateRegion?
    let latestReport: LocationReport?
    let mapDisplayMode: MapDisplayMode
    let onToggleMapMode: () -> Void
    @Environment(\.appTheme) private var theme
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            if isExpanded {
                VStack(spacing: 0) {
                    controlButton(icon: "location.fill") {
                        if let report = latestReport {
                            withAnimation {
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: report.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                ))
                            }
                        }
                    }
                    divider
                    controlButton(icon: "plus.magnifyingglass") {
                        zoom(by: 0.5)
                    }
                    divider
                    controlButton(icon: "minus.magnifyingglass") {
                        zoom(by: 2.0)
                    }
                    divider
                    controlButton(icon: mapDisplayModeIcon) {
                        onToggleMapMode()
                    }
                }
                .frame(width: 44)
                .background(theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.cardBorder.opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }

            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.cardBorder.opacity(0.8), lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
        .help("Locate, zoom, and switch map style")
    }

    private func controlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Divider()
            .frame(width: 32)
    }

    private var mapDisplayModeIcon: String {
        switch mapDisplayMode {
        case .standard: return "map"
        case .hybrid: return "square.3.layers.3d.down.right"
        case .imagery: return "globe.americas.fill"
        }
    }

    private func zoom(by multiplier: CLLocationDegrees) {
        let base = visibleRegion ?? latestReport.map {
            MKCoordinateRegion(
                center: $0.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        } ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
        )
        let nextSpan = MKCoordinateSpan(
            latitudeDelta: min(max(base.span.latitudeDelta * multiplier, 0.001), 120),
            longitudeDelta: min(max(base.span.longitudeDelta * multiplier, 0.001), 120)
        )
        withAnimation(.easeInOut(duration: 0.16)) {
            cameraPosition = .region(MKCoordinateRegion(center: base.center, span: nextSpan))
        }
    }
}

private struct HistoricalReportDot: View {
    let report: LocationReport
    let selectedFilter: MainMapView.TimeFilter
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(theme.cardBackground)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                Circle()
                    .fill(theme.primaryOrange.opacity(0.78))
                    .frame(width: 10, height: 10)
            }
            if selectedFilter != .live {
                Text(shortTime(report.timestamp))
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(theme.cardBackground.opacity(0.9), in: Capsule())
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func shortTime(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

private struct CustomTimelineSheet: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Custom Timeline")
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
            DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)

            Spacer()

            HStack {
                Button("Last 24 Hours") {
                    endDate = Date()
                    startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Apply") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.primaryOrange)
            }
        }
        .padding(22)
        .background(theme.background)
    }
}

// MARK: - MapMarkerCallout

struct MapMarkerCallout: View {
    let report: LocationReport
    let profileName: String
    let batteryLevel: Int?
    let locationName: String
    let iconStyle: FlipperIconStyle
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    FlipperMiniDevice(style: iconStyle)
                        .frame(width: 42, height: 24)
                    Text(profileName)
                        .font(.headline).foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let battery = batteryLevel {
                        BatteryPill(level: battery)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last seen \(relativeTime(report.timestamp))")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                    Text(locationName)
                        .font(.caption).fontWeight(.medium).foregroundStyle(theme.textPrimary)
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(report.confidence >= 70 ? theme.successGreen : theme.warningAmber)
                        .frame(width: 6, height: 6)
                    Text("Accuracy: \(report.confidence >= 70 ? "High" : "Medium")")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
            .padding(16)
            .background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            .frame(width: 260)
            
            // Pointer Down
            Image(systemName: "arrowtriangle.down.fill")
                .font(.caption)
                .foregroundStyle(theme.cardBackground)
                .offset(y: -8)
        }
    }

    private func relativeTime(_ ts: TimeInterval) -> String {
        let age = Date().timeIntervalSince1970 - ts
        if age < 60 { return "Just now" }
        if age < 3600 { return "\(Int(age/60)) min ago" }
        if age < 86400 { return "\(Int(age/3600)) hrs ago" }
        return "\(Int(age/86400)) days ago"
    }
}
