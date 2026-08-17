import Foundation
import Observation

@MainActor protocol RealtimeEventHandler: AnyObject {
    /// The socket (re)connected — a good time to resync, since events may have
    /// been missed while disconnected.
    func realtimeDidConnect(requiresResync: Bool)
    /// A sequence discontinuity or unhydrated event means at least one mutation
    /// could not be applied and the client must recover from REST snapshots.
    func realtimeNeedsResync()
    /// Carries the fully-hydrated chat summary from the event payload (preview,
    /// unread, ordering, flags) when present, so the handler can patch a single
    /// sidebar row instead of refetching the whole list. `chat` is nil only when
    /// the backend couldn't hydrate it — the handler should refetch in that case.
    func realtimeDidUpsertChat(chatID: String?, chat: Chat?)
    func realtimeDidDeleteChat(chatID: String?)
    /// Carries the fully-hydrated messages from the event payload, so the handler
    /// can apply them directly without refetching.
    func realtimeDidUpsertMessages(chatID: String?, messages: [Message])
    func realtimeDidUpdateReceipt(chatID: String?, entries: [[String: String]]?)
    func realtimeDidReceiveError(_ message: String)
}

@MainActor
@Observable
final class RealtimeService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketListenerTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var realtimeConnectionID = UUID()
    private var reconnectAttempt = 0
    private var lastSequence = 0
    private var hasConnectedBefore = false
    private var shouldRun = false
    private(set) var realtimeError: String?

    weak var eventHandler: RealtimeEventHandler?

    func start() {
        shouldRun = true
        guard webSocketTask == nil, reconnectTask == nil else { return }
        connect()
    }

    func stop() {
        shouldRun = false
        reconnectTask?.cancel()
        reconnectTask = nil
        closeConnection()
        reconnectAttempt = 0
        lastSequence = 0
    }

    // MARK: - Private

    private func connect() {
        guard shouldRun else { return }
        closeConnection()
        realtimeConnectionID = UUID()

        let webSocketTask = APIClient.makeWebSocketTask()
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        let connectionID = realtimeConnectionID
        webSocketListenerTask = Task { [weak self] in
            guard let self else { return }
            await self.listenForEvents(connectionID: connectionID)
        }

        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            await self.runHeartbeat(connectionID: connectionID)
        }
    }

    private func closeConnection() {
        webSocketListenerTask?.cancel()
        heartbeatTask?.cancel()
        webSocketListenerTask = nil
        heartbeatTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

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
                guard !Task.isCancelled, shouldRun else { return }
                scheduleReconnect(connectionID: connectionID, error: error)
                return
            }
        }
    }

    private func runHeartbeat(connectionID: UUID) async {
        while !Task.isCancelled, shouldRun, connectionID == realtimeConnectionID {
            do {
                try await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled,
                      connectionID == realtimeConnectionID,
                      let webSocketTask else { return }
                try await ping(webSocketTask)
            } catch {
                guard !Task.isCancelled, shouldRun else { return }
                scheduleReconnect(connectionID: connectionID, error: error)
                return
            }
        }
    }

    private func ping(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = PingContinuationGate(continuation)
            task.sendPing { error in
                gate.resume(with: error)
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
            reconnectAttempt = 0
            realtimeError = nil
            lastSequence = 0
            let requiresResync = hasConnectedBefore
            hasConnectedBefore = true
            await sendSubscriptionsAllChats()
            eventHandler?.realtimeDidConnect(requiresResync: requiresResync)
        case "subscriptions.updated":
            break
        case "error":
            if let message = envelope.message {
                eventHandler?.realtimeDidReceiveError("Realtime error: \(message)")
            }
        case "chat.upserted":
            trackSequence(in: envelope)
            // The event payload carries the hydrated chat summary; apply it
            // directly rather than refetching the chat list.
            let chat = (try? JSONDecoder.beeper.decode(ChatEntriesPayload.self, from: data))?.entries?.first
            eventHandler?.realtimeDidUpsertChat(chatID: envelope.chatID, chat: chat)
        case "chat.deleted":
            trackSequence(in: envelope)
            eventHandler?.realtimeDidDeleteChat(chatID: envelope.chatID)
        case "message.upserted":
            trackSequence(in: envelope)
            // The event payload already contains the hydrated message(s); apply
            // them directly rather than refetching the chat's history.
            let messages = (try? JSONDecoder.beeper.decode(MessageEntriesPayload.self, from: data))?.entries ?? []
            if messages.isEmpty, !(envelope.ids ?? []).isEmpty {
                eventHandler?.realtimeNeedsResync()
            } else {
                eventHandler?.realtimeDidUpsertMessages(chatID: envelope.chatID, messages: messages)
            }
        case "message.deleted":
            trackSequence(in: envelope)
            // Deleted events are hydrated with their retained original content
            // and an isDeleted marker, so merge them instead of removing rows.
            let messages = (try? JSONDecoder.beeper.decode(MessageEntriesPayload.self, from: data))?.entries ?? []
            if messages.isEmpty {
                eventHandler?.realtimeNeedsResync()
            } else {
                eventHandler?.realtimeDidUpsertMessages(chatID: envelope.chatID, messages: messages)
            }
        case "receipt.updated":
            trackSequence(in: envelope)
            eventHandler?.realtimeDidUpdateReceipt(chatID: envelope.chatID, entries: envelope.entries)
        default:
            break
        }
    }

    private func trackSequence(in envelope: WebSocketEnvelope) {
        guard let sequence = envelope.seq else {
            eventHandler?.realtimeNeedsResync()
            return
        }
        if sequence != lastSequence + 1 {
            eventHandler?.realtimeNeedsResync()
        }
        lastSequence = sequence
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

    private func scheduleReconnect(connectionID: UUID, error: Error) {
        guard shouldRun,
              connectionID == realtimeConnectionID,
              reconnectTask == nil else { return }

        closeConnection()
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        let baseDelay = min(pow(2.0, Double(attempt)), 30.0)
        // Jitter prevents every client from reconnecting to a recovering remote
        // deployment at the same instant.
        let delaySeconds = baseDelay + Double.random(in: 0 ... max(0.25, baseDelay * 0.25))

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            if attempt == 0 {
                self.realtimeError = error.localizedDescription
                self.eventHandler?.realtimeDidReceiveError("Realtime disconnected. Retrying…")
            }

            do {
                try await Task.sleep(for: .seconds(delaySeconds))
            } catch { return }

            guard !Task.isCancelled, self.shouldRun else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }
}

/// URLSession has been observed invoking a websocket ping callback more than
/// once while a connection is being cancelled. Checked continuations must be
/// resumed exactly once, so this gate atomically discards duplicate callbacks.
private final class PingContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(with error: Error?) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
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
    let seq: Int?

    enum CodingKeys: String, CodingKey {
        case type, requestID, chatID, message, ids, entries, seq
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        requestID = try? container.decodeIfPresent(String.self, forKey: .requestID)
        chatID = try? container.decodeIfPresent(String.self, forKey: .chatID)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        ids = try? container.decodeIfPresent([String].self, forKey: .ids)
        seq = try? container.decodeIfPresent(Int.self, forKey: .seq)
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
