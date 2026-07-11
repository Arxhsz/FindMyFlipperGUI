import Foundation

enum BackendStatus: Equatable {
    case starting
    case running
    case stopped
    case error(String)
}

enum BLEScanState: Equatable {
    case idle
    case scanning
    case notFound
    case error(String)
}

enum BLEConnectionState: Equatable {
    case idle
    case scanning
    case connecting(String)
    case connected(String)
    case unavailable(String)
    case error(String)
}

enum RefreshError: LocalizedError, Equatable {
    case authRequired
    case networkUnavailable
    case backendNotRunning
    case noReports
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .authRequired: return "Apple account not connected. Please reconnect your Apple account."
        case .networkUnavailable: return "Network unavailable. Please check your connection."
        case .backendNotRunning: return "Backend is not running. Please restart the backend."
        case .noReports: return "No reports found yet. Your Flipper may not have been seen by nearby Apple devices."
        case .unknown(let msg): return msg
        }
    }
}

enum BackendError: LocalizedError, Equatable {
    case notRunning
    case authRequired
    case noReports
    case networkUnavailable
    case decodingFailed
    case httpError(Int)
    case server(String)
    case vendorFilesMissing

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Backend is not running."
        case .authRequired: return "Apple authentication required."
        case .noReports: return "No reports available."
        case .networkUnavailable: return "Network unavailable."
        case .decodingFailed: return "Failed to decode server response."
        case .httpError(let code): return "HTTP error: \(code)"
        case .server(let message): return message
        case .vendorFilesMissing: return "pypush vendor files not found. See Backend/README.md."
        }
    }
}

enum KeychainError: LocalizedError, Equatable {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicateItem: return "A key with this ID already exists in Keychain."
        case .itemNotFound: return "Key not found in Keychain."
        case .unexpectedStatus(let status): return "Keychain error: \(status)"
        }
    }
}

enum KeysParseError: LocalizedError, Equatable {
    case fileNotReadable
    case invalidEncoding
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .fileNotReadable: return "Could not read the .keys file."
        case .invalidEncoding: return "File is not valid UTF-8 text."
        case .missingRequiredField(let field): return "Missing required field: \(field)"
        }
    }
}

struct KeysValidationError: Identifiable, Equatable {
    var id: String { field }
    var field: String
    var message: String
}
