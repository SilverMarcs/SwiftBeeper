import Foundation

enum InboxFilter: String, CaseIterable {
    case primary
    case archive
    case unread

    var label: String {
        switch self {
        case .primary: "Primary"
        case .archive: "Archive"
        case .unread: "Unread"
        }
    }

    var systemImage: String {
        switch self {
        case .primary: "tray.full"
        case .archive: "archivebox"
        case .unread: "envelope.badge"
        }
    }
}
