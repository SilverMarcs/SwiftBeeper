import Foundation

/// The kinds of shared content a chat's info screen browses.
enum ChatMediaKind: String, CaseIterable, Hashable, Sendable {
    case media
    case files
    case links

    var title: LocalizedStringResource {
        switch self {
        case .media: "Photos & Videos"
        case .files: "Files"
        case .links: "Links"
        }
    }

    var systemImage: String {
        switch self {
        case .media: "photo.on.rectangle"
        case .files: "doc"
        case .links: "link"
        }
    }

    /// Shown when the chat has none of this kind loaded.
    var emptyTitle: LocalizedStringResource {
        switch self {
        case .media: "No Photos or Videos"
        case .files: "No Files"
        case .links: "No Links"
        }
    }
}
