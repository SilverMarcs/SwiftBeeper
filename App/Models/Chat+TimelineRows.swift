import Foundation

extension Chat {
    /// This chat without the fields that change with every message or read:
    /// its preview, activity time, unread and mention state, and read
    /// position. Timeline rows only use its title, type, image, account and
    /// participants, so two copies that differ only in those fields compare
    /// equal and SwiftUI skips re-rendering the rows.
    var forTimelineRows: Chat {
        var copy = self
        copy.preview = nil
        copy.lastActivity = nil
        copy.unreadCount = 0
        copy.hasUnreadMention = nil
        copy.isMarkedUnread = nil
        copy.lastReadMessageSortKey = nil
        return copy
    }
}
