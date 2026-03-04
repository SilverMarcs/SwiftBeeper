import Foundation
import Observation

@MainActor
@Observable
final class ChatStore {
    private(set) var chats: [Chat] = []
    private(set) var messagesByChatID: [String: [Message]] = [:]
    private(set) var isLoadingChats = false
    private(set) var isLoadingMessages = false
    private(set) var chatsError: String?
    private(set) var messagesError: String?
    var selectedChatID: String?

    var selectedChat: Chat? {
        guard let selectedChatID else {
            return nil
        }
        return chats.first(where: { $0.id == selectedChatID })
    }

    func messages(for chatID: String) -> [Message] {
        messagesByChatID[chatID] ?? []
    }

    func loadChats(accessToken: String) async {
        guard !accessToken.isEmpty else {
            chats = []
            messagesByChatID = [:]
            selectedChatID = nil
            chatsError = nil
            messagesError = nil
            return
        }

        isLoadingChats = true
        defer { isLoadingChats = false }

        do {
            let response = try await APIClient.listChats(accessToken: accessToken)
            chats = response.items
            chatsError = nil

            if chats.contains(where: { $0.id == selectedChatID }) == false {
                selectedChatID = chats.first?.id
            }
        } catch {
            chatsError = error.localizedDescription
            chats = []
            messagesByChatID = [:]
            selectedChatID = nil
        }
    }

    func loadMessagesIfNeeded(for chatID: String, accessToken: String) async {
        if messagesByChatID[chatID] != nil {
            return
        }

        await loadMessages(for: chatID, accessToken: accessToken)
    }

    func loadMessages(for chatID: String, accessToken: String) async {
        guard !accessToken.isEmpty else {
            return
        }

        isLoadingMessages = true
        messagesError = nil
        defer { isLoadingMessages = false }

        do {
            let response = try await APIClient.listMessages(chatID: chatID, accessToken: accessToken)
            messagesByChatID[chatID] = response.items.sorted(by: { $0.sortKey < $1.sortKey })
        } catch {
            messagesError = error.localizedDescription
        }
    }
}
