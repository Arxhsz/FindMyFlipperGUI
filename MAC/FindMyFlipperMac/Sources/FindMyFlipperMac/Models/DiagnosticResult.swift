import Foundation

struct DiagnosticResult: Identifiable {
    var id: DiagnosticID
    var title: String
    var state: DiagnosticState
    var detail: String
    var fixAction: (() async -> Void)?
}

enum DiagnosticID: String, CaseIterable {
    case keysFileValid
    case privateKeyStored
    case hashedAdvKeyValid
    case appleAccessConnected
    case backendRunning
    case bluetoothPermission
    case flipperSelected
    case reportsEndpoint
}

enum DiagnosticState {
    case pass
    case fail
    case warning
    case running
    case pending
}
