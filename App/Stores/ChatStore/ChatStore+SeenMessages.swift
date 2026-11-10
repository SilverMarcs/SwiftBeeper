import Foundation

/// Keeps pushes quiet for messages the user has already seen on screen.
extension ChatStore {
    /// Records incoming messages as seen while their chat is on screen and
    /// Relay is frontmost, so their pushes stay quiet. This never marks the
    /// chat as read. Only recent messages count, so passing the whole
    /// timeline is cheap.
    func markVisibleMessagesSeen(_ candidates: [Message]) {
        guard notificationService.isAppActive, let chatID = visibleChatID,
              chatID == selectedChatID else { return }
        notificationService.markSeen(candidates.filter { $0.chatID == chatID && !$0.isHiddenThreadReply })
    }
}
