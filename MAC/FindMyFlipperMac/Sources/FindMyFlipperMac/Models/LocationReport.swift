import Foundation
import CoreLocation

struct LocationReport: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var timestamp: TimeInterval
    var isoDateTime: String
    /// Must be in range -90.0...90.0
    var lat: Double
    /// Must be in range -180.0...180.0
    var lon: Double
    /// 0-100
    var confidence: Int
    var status: Int
    var source: String
    var profileID: UUID

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
