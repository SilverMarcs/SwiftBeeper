import Foundation

/// Deleting and leaving chats from chat info.
extension ChatStore {
    /// Deletes the chat on its network where supported, otherwise leaves it,
    /// then drops it from the list. Throws the core's error for the caller
    /// to show.
    func deleteChat(_ chatID: String) async throws {
        try await APIClient.deleteChat(chatID: chatID)
        removeChatLocally(chatID)
    }

    /// Leaves a group, then drops it from the list.
    func leaveChat(_ chatID: String) async throws {
        try await APIClient.leaveChat(chatID: chatID)
        removeChatLocally(chatID)
    }
}
