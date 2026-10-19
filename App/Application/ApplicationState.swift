import Foundation

enum ApplicationState: Equatable {
    case starting
    case signIn(needsRecovery: Bool)
    case ready
    case failed(String)
}
