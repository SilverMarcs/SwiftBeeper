import Foundation

/// The messages above a reply whose quote was tapped: the one it quotes, what
/// that one quotes in turn, and so on, oldest first.
enum QuotedMessageChain {
    /// The most quoted messages shown above a reply.
    static let maximumLength = 8

    /// Each message as a standalone row, resolving quotes from the timeline's
    /// rows or the source's quoted-message lookup. The chain stops at a quote
    /// neither holds yet; the oldest row's `linkedMessage` is then nil.
    static func entries(
        from quoted: Message,
        timeline: [TimelineEntry],
        quotedMessages: [Message.ID: Message]
    ) -> [TimelineEntry] {
        func resolve(_ id: Message.ID?) -> Message? {
            guard let id, !id.isEmpty else { return nil }
            if let message = quotedMessages[id] { return message }
            for entry in timeline {
                if let message = entry.messages.first(where: { $0.id == id }) { return message }
            }
            return nil
        }

        var chain = [quoted]
        var seenIDs: Set<Message.ID> = [quoted.id]
        while chain.count < maximumLength, let next = resolve(chain[chain.count - 1].linkedMessageID),
              seenIDs.insert(next.id).inserted {
            chain.append(next)
        }
        return chain.reversed().map { message in
            .standalone(
                message,
                linkedMessage: resolve(message.linkedMessageID),
                threadRoot: resolve(message.broadcastThreadRootID)
            )
        }
    }

    /// The timeline rows the chain's messages have to themselves, which give
    /// up their bubble to the chain while it shows. A gallery's photo isn't
    /// one: the rest of its row would go with it. Nor is the reply's own.
    static func rowIDs(of chain: [TimelineEntry], in timeline: [TimelineEntry], replyRowID: Message.ID) -> Set<Message.ID> {
        var rowIDs = Set<Message.ID>()
        for quoted in chain where quoted.id != replyRowID {
            if let row = timeline.first(where: { $0.id == quoted.id }), row.galleryMessages.isEmpty {
                rowIDs.insert(row.id)
            }
        }
        return rowIDs
    }
}
