import Foundation

extension APIClient {
    /// The app's sidebar: pinned chats, then the first page by activity.
    static func recentShareChats() async throws -> [ShareChat] {
        let page: ShareChatPage = try await execute("list-chats", arguments: ShareChatQuery(query: nil))
        var seen = Set<String>()
        return ((page.pinned ?? []) + page.items).filter { seen.insert($0.id).inserted }
    }

    /// The same title search as the app's sidebar.
    static func searchShareChats(_ query: String) async throws -> [ShareChat] {
        let page: ShareChatPage = try await execute("search-chats", arguments: ShareChatQuery(query: query))
        return page.items
    }

    /// A chat the share sheet suggested, which may be outside the first page.
    static func shareChat(id: String) async throws -> ShareChat {
        struct Arguments: Encodable { let chatID: String }
        return try await execute("get-chat", arguments: Arguments(chatID: id))
    }

    /// Sends and returns once the server has the message.
    static func shareMessage(chatID: String, text: String?, attachment: MessageAttachmentInput?) async throws {
        struct Arguments: Encodable {
            let chatID: String
            let text: String?
            let attachment: MessageAttachmentInput?
        }
        try await executeRaw("share-message", arguments: Arguments(chatID: chatID, text: text, attachment: attachment))
    }
}

/// The primary inbox across every account, as the app lists it by default.
private struct ShareChatQuery: Encodable {
    let query: String?
    let inbox = "primary"
    let accountIDs: [String] = []
}
