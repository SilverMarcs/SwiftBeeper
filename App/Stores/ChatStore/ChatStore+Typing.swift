import Foundation

extension ChatStore {
    /// Each Matrix update replaces the complete list, rather than adding users.
    func updateTyping(_ participants: [ChatParticipant]) {
        guard notificationService.isAppActive else {
            clearTyping()
            return
        }
        let others = participants.filter {
            $0.isSelf != true && $0.id != currentUserProfile?.id
        }
        guard let first = others.first else {
            // A stop often overtakes the message in sync. Briefly retain the
            // row so the message can take its place without collapse/reinsert.
            expireTyping(after: .milliseconds(400))
            return
        }
        typingParticipants = others
        if typingBubble?.participant.id != first.id {
            typingBubble = TypingBubble(participant: first)
        }
        // The event has no expiry field. Bound its lifetime if a bridge misses
        // the stop event or sync stalls; there is no polling or outbound request.
        expireTyping(after: .seconds(30))
    }

    /// Only a new message from the typing participant can take over their row.
    /// History pages, edits, reactions, and our own messages keep their identity.
    func handoffTyping(to incoming: [Message]) {
        guard hasLoadedTimeline, let bubble = typingBubble,
              let message = incoming.filter({ message in
                  !message.isSender && !message.isDeletedMessage
                      && message.senderID == bubble.participant.id
                      && message.numericSortKey > (messages.last?.numericSortKey ?? .min)
                      && !messages.contains(where: { $0.id == message.id })
              }).min(by: { $0.numericSortKey < $1.numericSortKey }) else { return }

        typingMessageRowIDs[message.id] = bubble.id
        let remaining = typingParticipants.filter { $0.id != message.senderID }
        clearTyping()
        if !remaining.isEmpty { updateTyping(remaining) }
    }

    private func expireTyping(after delay: Duration) {
        typingExpirationTask?.cancel()
        guard typingBubble != nil else { return }
        typingExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.clearTyping()
        }
    }

    func clearTyping() {
        typingExpirationTask?.cancel()
        typingExpirationTask = nil
        typingParticipants = []
        typingBubble = nil
    }
}
