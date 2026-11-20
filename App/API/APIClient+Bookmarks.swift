import Foundation

/// Beeper's Bookmarks: private to the account, shared with its other Beeper
/// apps, and never sent to the chat.
extension APIClient {
    static func setMessageBookmark(chatID: String, messageID: String, bookmarked: Bool) async throws {
        struct Arguments: Encodable { let chatID: String; let messageID: String; let bookmarked: Bool }
        try await executeRaw("set-message-bookmark", arguments: Arguments(chatID: chatID, messageID: messageID, bookmarked: bookmarked))
    }

    /// The chat's bookmarked message IDs, and with `includeMessages` the
    /// messages too, most recently bookmarked first.
    static func listMessageBookmarks(chatID: String, includeMessages: Bool = false) async throws -> ListMessageBookmarksOutput {
        struct Arguments: Encodable { let chatID: String; let includeMessages: Bool }
        return try await execute("list-message-bookmarks", arguments: Arguments(chatID: chatID, includeMessages: includeMessages))
    }
}
