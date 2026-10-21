import Foundation
import Observation

@MainActor protocol RealtimeEventHandler: AnyObject {
    /// The event channel (re)connected — a good time to resync, since events may have
    /// been missed while disconnected.
    func realtimeDidConnect(requiresResync: Bool)
    /// A sequence discontinuity or unhydrated event means at least one mutation
    /// could not be applied, so the UI reloads from the local database.
    func realtimeNeedsResync()
    func realtimeDidUpdateNotificationPreferences()
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
    private var connectionHandle: UInt?
    private var eventListenerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var realtimeConnectionID = UUID()
    private var reconnectAttempt = 0
    private var lastSequence = 0
    private var hasConnectedBefore = false
    private var shouldRun = false
    private var messageChatIDs: Set<String> = []
    private(set) var realtimeError: String?

    weak var eventHandler: RealtimeEventHandler?

    func start() {
        shouldRun = true
        guard eventListenerTask == nil, reconnectTask == nil else { return }
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

    func reset() {
        stop()
        hasConnectedBefore = false
        messageChatIDs = []
    }

    func setMessageChats(_ ids: Set<String>) {
        guard ids != messageChatIDs else { return }
        messageChatIDs = ids
        Task { await updateSubscriptions() }
    }

    // MARK: - Private

    private func connect() {
        guard shouldRun else { return }
        closeConnection()
        realtimeConnectionID = UUID()

        let connectionID = realtimeConnectionID
        eventListenerTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (connection, stream) = try await MatrixRuntime.shared.events()
                guard !Task.isCancelled, connectionID == self.realtimeConnectionID else {
                    await MatrixRuntime.shared.closeRealtime(connection)
                    return
                }
                self.connectionHandle = connection
                for await data in stream {
                    guard !Task.isCancelled, connectionID == self.realtimeConnectionID else { return }
                    await self.handleEventPayload(data)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.scheduleReconnect(connectionID: connectionID, error: error)
            }
        }
    }

    private func closeConnection() {
        if let connection = connectionHandle {
            connectionHandle = nil
            Task { await MatrixRuntime.shared.closeRealtime(connection) }
        }
        eventListenerTask?.cancel()
        eventListenerTask = nil
    }


    private func handleEventPayload(_ data: Data?) async {
        guard
            let data,
            let envelope = try? JSONDecoder().decode(EventEnvelope.self, from: data)
        else { return }

        switch envelope.type {
        case "ready":
            reconnectAttempt = 0
            realtimeError = nil
            lastSequence = 0
            let requiresResync = hasConnectedBefore
            hasConnectedBefore = true
            await updateSubscriptions()
            eventHandler?.realtimeDidConnect(requiresResync: requiresResync)
        case "resync.required":
            eventHandler?.realtimeNeedsResync()
            eventHandler?.realtimeDidUpdateNotificationPreferences()
        case "push.preferences.changed":
            eventHandler?.realtimeDidUpdateNotificationPreferences()
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

    private func trackSequence(in envelope: EventEnvelope) {
        guard let sequence = envelope.seq else {
            eventHandler?.realtimeNeedsResync()
            return
        }
        if sequence != lastSequence + 1 {
            eventHandler?.realtimeNeedsResync()
        }
        lastSequence = sequence
    }

    private func updateSubscriptions() async {
        guard let connectionHandle else { return }
        do {
            try await MatrixRuntime.shared.setRealtimeSubscriptions(
                messageChatIDs: messageChatIDs.sorted(), connection: connectionHandle
            )
        } catch {
            eventHandler?.realtimeDidReceiveError("Could not subscribe to local updates.")
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
        let delaySeconds = baseDelay

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

private struct EventEnvelope: Decodable {
    let type: String
    let chatID: String?
    let ids: [String]?
    let entries: [[String: String]]?
    let seq: Int?

    enum CodingKeys: String, CodingKey {
        case type, chatID, ids, entries, seq
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        chatID = try? container.decodeIfPresent(String.self, forKey: .chatID)
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
