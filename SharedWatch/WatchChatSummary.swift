import Foundation

struct WatchChatSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let preview: String
    let unreadCount: Int
    let lastActivity: Date?
    let avatarURL: String?
    let isMuted: Bool?

    var lastActivityText: String? {
        guard let lastActivity else { return nil }
        let calendar = Calendar.current

        if calendar.isDateInToday(lastActivity) {
            return lastActivity.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(lastActivity) {
            return "Yesterday"
        }
        if let daysAgo = calendar.dateComponents([.day], from: lastActivity, to: .now).day,
           daysAgo < 7 {
            return lastActivity.formatted(.dateTime.weekday(.abbreviated))
        }
        return lastActivity.formatted(date: .numeric, time: .omitted)
    }

    init(
        id: String,
        title: String,
        preview: String,
        unreadCount: Int,
        lastActivity: Date?,
        avatarURL: String? = nil,
        isMuted: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.unreadCount = unreadCount
        self.lastActivity = lastActivity
        self.avatarURL = avatarURL
        self.isMuted = isMuted
    }
}
