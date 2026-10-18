import Foundation

nonisolated enum PushError: LocalizedError {
    case notConfigured
    case registrationFailed
    case invalidRegistration

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Notifications aren’t configured for this build."
        case .registrationFailed: "Couldn’t connect notifications. Try again when you’re online."
        case .invalidRegistration: "The notification server returned an invalid registration."
        }
    }
}
