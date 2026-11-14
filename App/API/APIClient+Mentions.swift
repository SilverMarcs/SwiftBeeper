import Foundation

extension APIClient {
    static func listUnreadMentions(chatID: String, after: String?) async throws -> ListMentionsOutput {
        struct Arguments: Encodable {
            let chatID: String
            let after: String?
        }
        return try await execute("list-unread-mentions", arguments: Arguments(chatID: chatID, after: after))
    }
}
