import Foundation

enum PhotoLibrarySaveError: LocalizedError {
    case unsupportedMedia
    case permissionDenied
    case unavailableMedia

    var errorDescription: String? {
        switch self {
        case .unsupportedMedia:
            String(localized: "This attachment can’t be saved to Photos.")
        case .permissionDenied:
            String(localized: "Allow Relay to add photos in your privacy settings, then try again.")
        case .unavailableMedia:
            String(localized: "This photo or video couldn’t be downloaded. Check your connection and try again.")
        }
    }
}
