import Foundation

/// Quoted messages older than the open timeline's loaded pages. Replies keep
/// only the quoted message's ID, so these come from the local database in one
/// batched lookup per page or sync update. Nothing here touches the network.
extension ChatStore {
    /// Reads the messages `incoming` quotes that neither the timeline nor an
    /// earlier lookup holds. Each ID is asked for once per open chat.
    func loadQuotedMessages(for incoming: [Message]) async {
        guard let chatID = selectedChatID else { return }
        let candidateIDs = Set(incoming.compactMap(\.linkedMessageID)).filter {
            !$0.isEmpty && quotedMessages[$0] == nil && !requestedQuotedMessageIDs.contains($0)
        }
        guard !candidateIDs.isEmpty else { return }
        // Quotes of messages on this page or an earlier one need no lookup.
        let loadedIDs = Set(messages.map(\.id)).union(incoming.map(\.id))
        let missingIDs = candidateIDs.subtracting(loadedIDs)
        guard !missingIDs.isEmpty else { return }

        let generation = timelineGeneration
        requestedQuotedMessageIDs.formUnion(missingIDs)
        do {
            let found = try await APIClient.getMessages(chatID: chatID, messageIDs: Array(missingIDs))
            guard generation == timelineGeneration else { return }
            for message in found { quotedMessages[message.id] = message }
        } catch {
            // Let a later page or update retry.
            guard generation == timelineGeneration else { return }
            requestedQuotedMessageIDs.subtract(missingIDs)
        }
    }
}
