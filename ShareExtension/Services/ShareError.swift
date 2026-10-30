import Foundation

nonisolated enum ShareError: LocalizedError {
    case notSignedIn, appBusy, attachmentTooLarge

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Open Relay and sign in to share."
        case .appBusy: "Relay is busy. Try again in a moment."
        case .attachmentTooLarge: "This file is too large to share from here. Send it from Relay instead."
        }
    }
}
