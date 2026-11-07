import Foundation

/// Where a composer sends: a chat's main timeline, or one of its threads.
struct ComposerTarget: Hashable, Sendable {
    let chatID: String
    var threadRootID: String?

    var isThread: Bool { threadRootID != nil }
}
