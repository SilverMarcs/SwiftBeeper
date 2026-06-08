import Foundation
import Observation

@MainActor protocol RealtimeEventHandler: AnyObject {
    /// The socket (re)connected — a good time to resync, since events may have
    /// been missed while disconnected.
    func realtimeDidConnect()
    /// Carries the fully-hydrated chat summary from the event payload (preview,
    /// unread, ordering, flags) when present, so the handler can patch a single
    /// sidebar row instead of refetching the whole list. `chat` is nil only when
    /// the backend couldn't hydrate it — the handler should refetch in that case.
    func realtimeDidUpsertChat(chatID: String?, chat: Chat?)
    func realtimeDidDeleteChat(chatID: String?)
    /// Carries the fully-hydrated messages from the event payload, so the handler
    /// can apply them directly without refetching.
    func realtimeDidUpsertMessages(chatID: String?, messages: [Message])
    func realtimeDidDeleteMessage(chatID: String?)
    func realtimeDidUpdateReceipt(chatID: String?, entries: [[String: String]]?)
    func realtimeDidReceiveError(_ message: String)
}

@MainActor
@Observable
final class RealtimeService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketListenerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var realtimeConnectionID = UUID()
    private(set) var realtimeError: String?

    weak var eventHandler: RealtimeEventHandler?

    func start() {
        stop()
        realtimeConnectionID = UUID()

        let webSocketTask = APIClient.makeWebSocketTask()
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        let connectionID = realtimeConnectionID
        webSocketListenerTask = Task { [weak self] in
            guard let self else { return }
            await self.listenForEvents(connectionID: connectionID)
        }
    }

    func stop() {
        webSocketListenerTask?.cancel()
        reconnectTask?.cancel()

        webSocketListenerTask = nil
        reconnectTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Private

    private func listenForEvents(connectionID: UUID) async {
        while !Task.isCancelled {
            guard let webSocketTask else { return }

            do {
                let message = try await webSocketTask.receive()

                switch message {
                case .string(let text):
                    await handleWebSocketPayload(text.data(using: .utf8))
                case .data(let data):
                    await handleWebSocketPayload(data)
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled else { return }
                scheduleReconnect(connectionID: connectionID)
                return
            }
        }
    }

    private func handleWebSocketPayload(_ data: Data?) async {
        guard
            let data,
            let envelope = try? JSONDecoder().decode(WebSocketEnvelope.self, from: data)
        else { return }

        switch envelope.type {
        case "ready":
            await sendSubscriptionsAllChats()
            eventHandler?.realtimeDidConnect()
        case "subscriptions.updated":
            break
        case "error":
            if let message = envelope.message {
                eventHandler?.realtimeDidReceiveError("Realtime error: \(message)")
            }
        case "chat.upserted":
            // The event payload carries the hydrated chat summary; apply it
            // directly rather than refetching the chat list.
            let chat = (try? JSONDecoder.beeper.decode(ChatEntriesPayload.self, from: data))?.entries?.first
            eventHandler?.realtimeDidUpsertChat(chatID: envelope.chatID, chat: chat)
        case "chat.deleted":
            eventHandler?.realtimeDidDeleteChat(chatID: envelope.chatID)
        case "message.upserted":
            // The event payload already contains the hydrated message(s); apply
            // them directly rather than refetching the chat's history.
            let messages = (try? JSONDecoder.beeper.decode(MessageEntriesPayload.self, from: data))?.entries ?? []
            eventHandler?.realtimeDidUpsertMessages(chatID: envelope.chatID, messages: messages)
        case "message.deleted":
            eventHandler?.realtimeDidDeleteMessage(chatID: envelope.chatID)
        case "receipt.updated":
            eventHandler?.realtimeDidUpdateReceipt(chatID: envelope.chatID, entries: envelope.entries)
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
            eventHandler?.realtimeDidReceiveError("Could not set realtime subscriptions: \(error.localizedDescription)")
        }
    }

    private func scheduleReconnect(connectionID: UUID) {
        guard connectionID == realtimeConnectionID else { return }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }

            self.eventHandler?.realtimeDidReceiveError("Realtime disconnected. Retrying…")

            do {
                try await Task.sleep(for: .seconds(2))
            } catch { return }

            guard !Task.isCancelled, self.realtimeConnectionID == connectionID else { return }
            self.start()
        }
    }
}

private struct WebSocketEnvelope: Decodable {
    let type: String
    let requestID: String?
    let chatID: String?
    let message: String?
    let ids: [String]?
    let entries: [[String: String]]?

    enum CodingKeys: String, CodingKey {
        case type, requestID, chatID, message, ids, entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        requestID = try? container.decodeIfPresent(String.self, forKey: .requestID)
        chatID = try? container.decodeIfPresent(String.self, forKey: .chatID)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        ids = try? container.decodeIfPresent([String].self, forKey: .ids)
        // entries may contain non-string values (bools, nulls) in message events;
        // only receipt events use this field, so fall back to nil on type mismatch.
        entries = try? container.decodeIfPresent([[String: String]].self, forKey: .entries)
    }
}

private struct MessageEntriesPayload: Decodable {
    let entries: [Message]?
}

private struct ChatEntriesPayload: Decodable {
    let entries: [Chat]?
}

private struct SubscriptionsSetCommand: Encodable {
    let type = "subscriptions.set"
    let requestID: String
    let chatIDs: [String]
}
