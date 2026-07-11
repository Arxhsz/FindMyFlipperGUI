import Foundation

struct BLEDeviceScorer {
    func score(name: String?, rssi: Int, lastSeen: Date = Date()) -> BLEDeviceScore {
        let secondsSinceSeen = Date().timeIntervalSince(lastSeen)
        let lower = (name ?? "").lowercased()
        let isFlipperName = lower.contains("flipper") || lower.contains("fz")
        if isFlipperName && rssi >= -65 && secondsSinceSeen < 60 { return .recommended }
        if rssi < -80 { return .weak }
        if isFlipperName || rssi >= -75 { return .possibleFlipper }
        return .unknown
    }
}
