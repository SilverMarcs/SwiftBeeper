import Foundation
import Observation

@Observable
final class ChatStore {
    private(set) var chats: [Chat] = []
    private(set) var messagesByChatID: [String: [Message]] = [:]
    private(set) var isLoadingChats = false
    private(set) var isLoadingMessages = false
    private(set) var isSendingMessage = false
    private(set) var chatsError: String?
    private(set) var messagesError: String?
    var selectedChatID: String?
    var searchQuery: String = ""
    var searchResults: [Chat]?
    var isSearching = false
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketListenerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var scheduledChatsRefreshTask: Task<Void, Never>?
    private var scheduledMessagesRefreshTasks: [String: Task<Void, Never>] = [:]
    private var realtimeConnectionID = UUID()
    private var currentAccessToken = ""

    var displayedChats: [Chat] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return chats
        }
        return searchResults ?? chats
    }

    var selectedChat: Chat? {
        guard let selectedChatID else {
            return nil
        }
        return chats.first(where: { $0.id == selectedChatID })
    }

    func searchChats() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            searchResults = nil
            isSearching = false
            return
        }

        isSearching = true
        do {
            let response = try await APIClient.searchChats(query: trimmed, accessToken: currentAccessToken)
            searchResults = response.items
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    func messages(for chatID: String) -> [Message] {
        messagesByChatID[chatID] ?? []
    }

    func updateAccessToken(_ accessToken: String) async {
        if accessToken == currentAccessToken {
            return
        }

        currentAccessToken = accessToken

        if accessToken.isEmpty {
            stopRealtime()
            chats = []
            messagesByChatID = [:]
            selectedChatID = nil
            chatsError = nil
            messagesError = nil
            return
        }

        await loadChats(accessToken: accessToken)
        startRealtime(accessToken: accessToken)
    }

    func loadChats() async {
        await loadChats(accessToken: currentAccessToken)
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

    func loadMessagesIfNeeded(for chatID: String) async {
        await loadMessagesIfNeeded(for: chatID, accessToken: currentAccessToken)
    }

    func loadMessagesIfNeeded(for chatID: String, accessToken: String) async {
        if messagesByChatID[chatID] != nil {
            return
        }

        await loadMessages(for: chatID, accessToken: accessToken)
    }

    func loadMessages(for chatID: String) async {
        await loadMessages(for: chatID, accessToken: currentAccessToken)
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

    func sendTextMessage(_ text: String, to chatID: String) async -> Bool {
        await sendTextMessage(text, to: chatID, accessToken: currentAccessToken)
    }

    func sendTextMessage(_ text: String, to chatID: String, accessToken: String) async -> Bool {
        guard accessToken.isEmpty == false else {
            return false
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else {
            return false
        }

        isSendingMessage = true
        defer { isSendingMessage = false }

        do {
            _ = try await APIClient.sendMessage(chatID: chatID, text: trimmedText, accessToken: accessToken)
            messagesError = nil
            scheduleChatsRefresh(accessToken: accessToken)
            scheduleMessagesRefresh(chatID: chatID, accessToken: accessToken)
            return true
        } catch {
            messagesError = error.localizedDescription
            return false
        }
    }

    private func startRealtime(accessToken: String) {
        stopRealtime()
        realtimeConnectionID = UUID()

        let webSocketTask = APIClient.makeWebSocketTask(accessToken: accessToken)
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        let connectionID = realtimeConnectionID
        webSocketListenerTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.listenForEvents(connectionID: connectionID, accessToken: accessToken)
        }
    }

    private func stopRealtime() {
        webSocketListenerTask?.cancel()
        reconnectTask?.cancel()
        scheduledChatsRefreshTask?.cancel()

        for task in scheduledMessagesRefreshTasks.values {
            task.cancel()
        }
        scheduledMessagesRefreshTasks = [:]

        webSocketListenerTask = nil
        reconnectTask = nil
        scheduledChatsRefreshTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func listenForEvents(connectionID: UUID, accessToken: String) async {
        while Task.isCancelled == false {
            guard let webSocketTask else {
                return
            }

            do {
                let message = try await webSocketTask.receive()

                switch message {
                case .string(let text):
                    await handleWebSocketPayload(text.data(using: .utf8), accessToken: accessToken)
                case .data(let data):
                    await handleWebSocketPayload(data, accessToken: accessToken)
                @unknown default:
                    break
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }

                scheduleReconnect(connectionID: connectionID, accessToken: accessToken)
                return
            }
        }
    }

    private func handleWebSocketPayload(_ data: Data?, accessToken: String) async {
        guard
            let data,
            let envelope = try? JSONDecoder().decode(WebSocketEnvelope.self, from: data)
        else {
            return
        }

        switch envelope.type {
        case "ready":
            await sendSubscriptionsAllChats()
        case "subscriptions.updated":
            break
        case "error":
            if let message = envelope.message {
                messagesError = "Realtime error: \(message)"
            }
        case "chat.upserted", "chat.deleted":
            scheduleChatsRefresh(accessToken: accessToken)
        case "message.upserted", "message.deleted":
            scheduleChatsRefresh(accessToken: accessToken)

            guard let chatID = envelope.chatID else {
                return
            }

            let shouldRefreshMessages = selectedChatID == chatID || messagesByChatID[chatID] != nil
            if shouldRefreshMessages {
                scheduleMessagesRefresh(chatID: chatID, accessToken: accessToken)
            }
        default:
            break
        }
    }

    private func sendSubscriptionsAllChats() async {
        guard let webSocketTask else {
            return
        }

        let command = SubscriptionsSetCommand(
            requestID: "subscriptions-\(UUID().uuidString)",
            chatIDs: ["*"]
        )

        do {
            let payload = try JSONEncoder().encode(command)
            try await webSocketTask.send(.data(payload))
        } catch {
            messagesError = "Could not set realtime subscriptions: \(error.localizedDescription)"
        }
    }

    private func scheduleReconnect(connectionID: UUID, accessToken: String) {
        guard connectionID == realtimeConnectionID else {
            return
        }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else {
                return
            }

            self.messagesError = "Realtime disconnected. Retrying…"

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }

            guard Task.isCancelled == false, self.realtimeConnectionID == connectionID else {
                return
            }

            self.startRealtime(accessToken: accessToken)
        }
    }

    private func scheduleChatsRefresh(accessToken: String) {
        scheduledChatsRefreshTask?.cancel()
        scheduledChatsRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard Task.isCancelled == false else {
                return
            }

            await self.loadChats(accessToken: accessToken)
        }
    }

    private func scheduleMessagesRefresh(chatID: String, accessToken: String) {
        scheduledMessagesRefreshTasks[chatID]?.cancel()
        scheduledMessagesRefreshTasks[chatID] = Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.scheduledMessagesRefreshTasks[chatID] = nil
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard Task.isCancelled == false else {
                return
            }

            await self.loadMessages(for: chatID, accessToken: accessToken)
        }
    }
}

private struct WebSocketEnvelope: Decodable {
    let type: String
    let requestID: String?
    let chatID: String?
    let message: String?
}

private struct SubscriptionsSetCommand: Encodable {
    let type = "subscriptions.set"
    let requestID: String
    let chatIDs: [String]
}
