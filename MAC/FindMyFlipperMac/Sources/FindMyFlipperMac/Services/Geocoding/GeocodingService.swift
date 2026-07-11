import Foundation
import CoreLocation

@MainActor
final class GeocodingService: ObservableObject {
    @Published var cache: [String: String] = [:]
    private let geocoder = CLGeocoder()

    func locationName(for report: LocationReport) -> String {
        let key = "\(String(format: "%.3f", report.lat)),\(String(format: "%.3f", report.lon))"
        if let cached = cache[key] {
            return cached
        }
        
        // Return an explicit loading state while reverse geocoding completes.
        Task {
            if let name = await fetchName(for: report.coordinate) {
                self.cache[key] = name
            }
        }
        return "Locating..."
    }

    private func fetchName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let p = placemarks.first {
                var components = [String]()
                if let locality = p.locality { components.append(locality) }
                if let adminArea = p.administrativeArea { components.append(adminArea) }
                if let country = p.country { components.append(country) }
                return components.joined(separator: ", ")
            }
        } catch {
            print("Geocoding error: \(error)")
        }
        return nil
    }
}
