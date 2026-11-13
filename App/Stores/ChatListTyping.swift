import Foundation

/// Typing for every chat, shown in place of the chat list's previews. The core
/// pushes each room's typing changes from sync; nothing here polls.
///
/// Deliberately not observable itself: each chat's row observes only its own
/// `ChatTypingState`, so one chat's typing doesn't re-render the other rows,
/// and the list itself is never re-sorted or re-diffed.
@MainActor
final class ChatListTyping {
    /// Kept once made, even after typing stops: a row observes its instance,
    /// so replacing one would leave that row watching a stale copy. One small
    /// object per chat shown or typed in this session.
    private var states: [Chat.ID: ChatTypingState] = [:]

    /// The state a chat's row reads, made on first use.
    func state(for chatID: Chat.ID) -> ChatTypingState {
        if let state = states[chatID] { return state }
        let state = ChatTypingState()
        states[chatID] = state
        return state
    }

    func update(chatID: Chat.ID, participants: [ChatParticipant], previewID: Message.ID?) {
        // A stop for a chat that never had typing needs no state.
        guard !participants.isEmpty || states[chatID] != nil else { return }
        state(for: chatID).update(participants, previewID: previewID)
    }

    /// Ends the typing of whoever sent the chat's new last message.
    func chatUpdated(_ chat: Chat) {
        states[chat.id]?.previewChanged(to: chat.preview)
    }

    /// Clears every chat, as when updates stop or events may have been dropped.
    func clearAll() {
        for state in states.values {
            state.clear()
        }
    }
}
