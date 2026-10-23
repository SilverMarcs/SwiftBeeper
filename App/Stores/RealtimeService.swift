import Foundation

/// Streams change events from the in-process Matrix core to a single handler.
@MainActor
final class RealtimeService {
    var onEvent: (RealtimeEvent) -> Void = { _ in }

    private var connectionHandle: UInt?
    private var listenerTask: Task<Void, Never>?
    private var lastSequence = 0
    private var hasConnectedBefore = false
    private var messageChatIDs: Set<String> = []

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
        } catch {
            // The core could not start. The next activation tries again.
            guard !Task.isCancelled else { return }
            listenerTask = nil
            onEvent(.failed("Could not start local updates."))
        }
    }

    private func handle(_ data: Data) async {
        guard let envelope = try? JSONDecoder().decode(EventEnvelope.self, from: data) else { return }

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
            if let chat = (try? JSONDecoder.beeper.decode(EntriesPayload<Chat>.self, from: data))?.entries?.first {
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
            let messages = (try? JSONDecoder.beeper.decode(EntriesPayload<Message>.self, from: data))?.entries ?? []
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
