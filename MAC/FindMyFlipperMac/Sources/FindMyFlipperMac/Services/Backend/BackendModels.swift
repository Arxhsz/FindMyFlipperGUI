import Foundation

struct HealthResponse: Codable {
    var status: String
    var version: String
}

struct ReportsResponse: Codable {
    var ok: Bool
    var reports: [LocationReportDTO]
    var error: String?
    var message: String?
    var foundKeys: [String]?
    var missingKeys: [String]?
}

struct LocationReportDTO: Codable {
    var id: String
    var timestamp: TimeInterval
    var isoDateTime: String
    var lat: Double
    var lon: Double
    var confidence: Int
    var status: Int
    var source: String

    func toLocationReport(profileID: UUID) -> LocationReport {
        LocationReport(
            id: id, timestamp: timestamp, isoDateTime: isoDateTime,
            lat: lat, lon: lon, confidence: confidence,
            status: status, source: source, profileID: profileID
        )
    }
}

struct AuthStatusResponse: Codable {
    var connected: Bool
    var accountIdentifier: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case connected
        case accountIdentifier = "account_identifier"
        case error
    }
}

struct AuthConnectResponse: Codable {
    var ok: Bool
    var accountIdentifier: String?
    var requiresCredentials: Bool?
    var requires2FA: Bool?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case accountIdentifier = "account_identifier"
        case requiresCredentials = "requires_credentials"
        case requires2FA = "requires_2fa"
        case error
    }
}

struct AuthRefreshResponse: Codable {
    var ok: Bool
    var error: String?
}

struct GenerateKeysResponse: Codable {
    var ok: Bool
    var rawContent: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case rawContent = "raw_content"
        case error
    }
}

struct StartAnisetteResponse: Codable {
    var ok: Bool
    var installed: Bool?
    var started: Bool?
    var runtime: String?
    var message: String?
    var error: String?
    var detail: String?
}

struct StartAnisetteRequest: Codable {
    var installIfMissing: Bool

    enum CodingKeys: String, CodingKey {
        case installIfMissing = "install_if_missing"
    }
}

struct AuthConnectRequest: Codable {
    var username: String?
    var password: String?
    var secondFactor: String
    var code: String?

    enum CodingKeys: String, CodingKey {
        case username
        case password
        case secondFactor = "second_factor"
        case code
    }
}

struct KeyValidationResponse: Codable {
    var valid: Bool
    var errors: [String]
    var parsedFields: [String: String]

    enum CodingKeys: String, CodingKey {
        case valid
        case errors
        case parsedFields = "parsedFields"
    }
}

struct KeysValidateRequest: Codable {
    var rawContent: String
    enum CodingKeys: String, CodingKey { case rawContent = "raw_content" }
}

struct ReportsRequest: Codable {
    var hashedAdvKeyBase64: String
    var privateKeyBase64: String
    var hours: Int
    enum CodingKeys: String, CodingKey {
        case hashedAdvKeyBase64 = "hashed_adv_key_base64"
        case privateKeyBase64 = "private_key_base64"
        case hours
    }
}
