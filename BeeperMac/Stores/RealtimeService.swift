import Foundation
import Observation

@Observable
final class RealtimeService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketListenerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var scheduledChatsRefreshTask: Task<Void, Never>?
    private var scheduledMessagesRefreshTasks: [String: Task<Void, Never>] = [:]
    private var realtimeConnectionID = UUID()
    private(set) var realtimeError: String?

    @ObservationIgnored var onRefreshChats: (@Sendable () async -> Void)?
    @ObservationIgnored var onRefreshMessages: (@Sendable (String) async -> Void)?
    @ObservationIgnored var onRealtimeError: (@Sendable (String) -> Void)?

    /// Which chatID is currently selected (used to decide whether to refresh messages).
    var selectedChatID: String?
    /// Which chatIDs have loaded messages (used to decide whether to refresh messages).
    @ObservationIgnored var loadedMessageChatIDs: (@Sendable () -> Set<String>)?

    func start(accessToken: String) {
        stop()
        realtimeConnectionID = UUID()

        let webSocketTask = APIClient.makeWebSocketTask(accessToken: accessToken)
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        let connectionID = realtimeConnectionID
        webSocketListenerTask = Task { [weak self] in
            guard let self else { return }
            await self.listenForEvents(connectionID: connectionID, accessToken: accessToken)
        }
    }

    func stop() {
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

    func scheduleChatsRefresh() {
        scheduledChatsRefreshTask?.cancel()
        scheduledChatsRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }

            guard !Task.isCancelled else { return }
            await self.onRefreshChats?()
        }
    }

    func scheduleMessagesRefresh(chatID: String) {
        scheduledMessagesRefreshTasks[chatID]?.cancel()
        scheduledMessagesRefreshTasks[chatID] = Task { [weak self] in
            guard let self else { return }

            defer {
                self.scheduledMessagesRefreshTasks[chatID] = nil
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }

            guard !Task.isCancelled else { return }
            await self.onRefreshMessages?(chatID)
        }
    }

    // MARK: - Private

    private func listenForEvents(connectionID: UUID, accessToken: String) async {
        while !Task.isCancelled {
            guard let webSocketTask else { return }

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
                guard !Task.isCancelled else { return }
                scheduleReconnect(connectionID: connectionID, accessToken: accessToken)
                return
            }
        }
    }

    private func handleWebSocketPayload(_ data: Data?, accessToken: String) async {
        guard
            let data,
            let envelope = try? JSONDecoder().decode(WebSocketEnvelope.self, from: data)
        else { return }

        switch envelope.type {
        case "ready":
            await sendSubscriptionsAllChats()
        case "subscriptions.updated":
            break
        case "error":
            if let message = envelope.message {
                onRealtimeError?("Realtime error: \(message)")
            }
        case "chat.upserted", "chat.deleted":
            scheduleChatsRefresh()
        case "message.upserted", "message.deleted":
            scheduleChatsRefresh()

            guard let chatID = envelope.chatID else { return }

            let loadedIDs = loadedMessageChatIDs?() ?? []
            let shouldRefreshMessages = selectedChatID == chatID || loadedIDs.contains(chatID)
            if shouldRefreshMessages {
                scheduleMessagesRefresh(chatID: chatID)
            }
        default:
            break
        }
    }

    private func sendSubscriptionsAllChats() async {
        guard let webSocketTask else { return }

        let command = SubscriptionsSetCommand(
            requestID: "subscriptions-\(UUID().uuidString)",
            chatIDs: ["*"]
        )

        do {
            let payload = try JSONEncoder().encode(command)
            try await webSocketTask.send(.data(payload))
        } catch {
            onRealtimeError?("Could not set realtime subscriptions: \(error.localizedDescription)")
        }
    }

    private func scheduleReconnect(connectionID: UUID, accessToken: String) {
        guard connectionID == realtimeConnectionID else { return }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }

            self.onRealtimeError?("Realtime disconnected. Retrying…")

            do {
                try await Task.sleep(for: .seconds(2))
            } catch { return }

            guard !Task.isCancelled, self.realtimeConnectionID == connectionID else { return }
            self.start(accessToken: accessToken)
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
