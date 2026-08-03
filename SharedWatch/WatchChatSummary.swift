import Foundation

struct WatchChatSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let preview: String
    let unreadCount: Int
    let lastActivity: Date?
    let avatarURL: String?

    init(
        id: String,
        title: String,
        preview: String,
        unreadCount: Int,
        lastActivity: Date?,
        avatarURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.unreadCount = unreadCount
        self.lastActivity = lastActivity
        self.avatarURL = avatarURL
    }
}
