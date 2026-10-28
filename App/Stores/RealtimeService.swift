import Foundation

/// Streams change events from the in-process Matrix core to a single handler.
/// Chat events always flow; message events only for the subscribed chats.
@MainActor
final class RealtimeService {
    var onEvent: (RealtimeEvent) -> Void = { _ in }

    private var connectionHandle: UInt?
    private var listenerTask: Task<Void, Never>?
    /// The last event sequence number seen. The event buffers are bounded,
    /// so a gap means events were dropped and the UI must resync.
    private var lastSequence = 0
    private var hasConnectedBefore = false
    private var messageChatIDs: Set<String> = []

    /// Starts listening unless a listener is already running.
    func start() {
        guard listenerTask == nil else { return }
        listenerTask = Task { [weak self] in
            await self?.listen()
        }
    }

    func stop() {
        if let connectionHandle {
            self.connectionHandle = nil
            Task { await MatrixRuntime.shared.closeRealtime(connectionHandle) }
        }
        listenerTask?.cancel()
        listenerTask = nil
        lastSequence = 0
        onEvent(.disconnected)
    }

    /// Stops and forgets the session, so the next connection is not a reconnect.
    func reset() {
        stop()
        hasConnectedBefore = false
        messageChatIDs = []
    }

    /// The chats whose message events the core should deliver.
    func setMessageChats(_ ids: Set<String>) {
        guard ids != messageChatIDs else { return }
        messageChatIDs = ids
        Task { await updateSubscriptions() }
    }

    // MARK: - Private

    private func listen() async {
        do {
            let (connection, stream) = try await MatrixRuntime.shared.events()
            guard !Task.isCancelled else {
                await MatrixRuntime.shared.closeRealtime(connection)
                return
            }
            connectionHandle = connection
            for await data in stream {
                guard !Task.isCancelled else { return }
                await handle(data)
            }
            // The core closed the stream; let the next start() reconnect.
            guard !Task.isCancelled else { return }
            connectionHandle = nil
            listenerTask = nil
            onEvent(.disconnected)
        } catch {
            // The core could not start. The next activation tries again.
            guard !Task.isCancelled else { return }
            listenerTask = nil
            onEvent(.failed("Could not start local updates."))
        }
    }

    private func handle(_ data: Data) async {
        let decoder = JSONDecoder.beeper
        guard let envelope = try? decoder.decode(EventEnvelope.self, from: data) else { return }

        switch envelope.type {
        case "ready":
            lastSequence = 0
            let requiresResync = hasConnectedBefore
            hasConnectedBefore = true
            await updateSubscriptions()
            onEvent(.connected(requiresResync: requiresResync))
        case "resync.required":
            onEvent(.resyncRequired)
            onEvent(.notificationPreferencesChanged)
        case "push.preferences.changed":
            onEvent(.notificationPreferencesChanged)
        case "chat.upserted":
            trackSequence(in: envelope)
            if let chat = (try? decoder.decode(EntriesPayload<Chat>.self, from: data))?.entries?.first {
                onEvent(.chatUpserted(chat))
            } else {
                onEvent(.resyncRequired)
            }
        case "chat.deleted":
            trackSequence(in: envelope)
            if let chatID = envelope.chatID {
                onEvent(.chatDeleted(chatID: chatID))
            } else {
                onEvent(.resyncRequired)
            }
        case "message.upserted":
            trackSequence(in: envelope)
            // Deletions arrive here too, as messages with an isDeleted marker.
            let messages = (try? decoder.decode(EntriesPayload<Message>.self, from: data))?.entries ?? []
            if let chatID = envelope.chatID, !messages.isEmpty {
                onEvent(.messagesUpserted(chatID: chatID, messages: messages))
            } else {
                onEvent(.resyncRequired)
            }
        case "receipt.updated":
            trackSequence(in: envelope)
            if let chatID = envelope.chatID,
               let readKey = envelope.entries?.first?["lastReadByOtherSortKey"] {
                onEvent(.receiptUpdated(chatID: chatID, lastReadByOtherSortKey: readKey))
            }
        case "typing.updated":
            trackSequence(in: envelope)
            if let chatID = envelope.chatID {
                let participants = (try? decoder.decode(EntriesPayload<ChatParticipant>.self, from: data))?.entries ?? []
                onEvent(.typingUpdated(chatID: chatID, participants: participants))
            }
        default:
            break
        }
    }

    private func trackSequence(in envelope: EventEnvelope) {
        if envelope.seq != lastSequence + 1 {
            onEvent(.resyncRequired)
        }
        lastSequence = envelope.seq ?? lastSequence
    }

    private func updateSubscriptions() async {
        guard let connectionHandle else { return }
        do {
            try await MatrixRuntime.shared.setRealtimeSubscriptions(
                messageChatIDs: messageChatIDs.sorted(), connection: connectionHandle
            )
        } catch {
            onEvent(.failed("Could not subscribe to local updates."))
        }
    }
}
