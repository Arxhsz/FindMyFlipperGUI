import SwiftUI

enum AppDestination: Hashable {
    case map
    case dashboard
    case reports
    case flipperDetail
    case profiles
    case settings
    case onboarding
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var currentDestination: AppDestination = .map
}
