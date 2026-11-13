import Foundation

/// What the quoted-message overlay shows: a quoted message and, below it, the
/// reply that quotes it, each as a standalone row.
struct QuotedMessageContext: Equatable {
    let quoted: TimelineEntry
    let reply: TimelineEntry?

    /// Resolves each message's own quote from the timeline's rows, so a quoted
    /// message that is itself a reply shows what it replies to.
    init(quoted: Message, reply: Message?, entries: [TimelineEntry], quotedMessages: [Message.ID: Message]) {
        func entry(for message: Message, known: [Message]) -> TimelineEntry {
            let row = entries.first { $0.message.id == message.id }
            func resolve(_ id: Message.ID?) -> Message? {
                guard let id else { return nil }
                return known.first { $0.id == id }
                    ?? entries.first { $0.message.id == id }?.message
                    ?? quotedMessages[id]
            }
            return .standalone(
                message,
                linkedMessage: row?.linkedMessage ?? resolve(message.linkedMessageID),
                threadRoot: row?.threadRoot ?? resolve(message.broadcastThreadRootID)
            )
        }
        self.quoted = entry(for: quoted, known: [])
        self.reply = reply.map { entry(for: $0, known: [quoted]) }
    }
}
