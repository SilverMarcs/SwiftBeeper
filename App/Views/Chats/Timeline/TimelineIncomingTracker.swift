import Foundation

/// Identifies live appends within one loaded viewport, excluding opening a
/// chat, jumping to a message, pagination, and updates to existing messages.
struct TimelineIncomingTracker: Equatable {
    let target: ComposerTarget
    let windowID: UUID
    let isLoaded: Bool
    let hasMoreNewer: Bool
    let lastMessageID: Message.ID?
    let lastSortKey: Int64?

    func arrivals(since previous: Self, in messages: [Message]) -> Set<Message.ID> {
        guard previous.target == target, previous.windowID == windowID,
              previous.isLoaded, isLoaded, !previous.hasMoreNewer, !hasMoreNewer,
              lastMessageID != previous.lastMessageID else { return [] }

        let appended: ArraySlice<Message>
        if let lastID = previous.lastMessageID {
            guard let index = messages.firstIndex(where: { $0.id == lastID }) else { return [] }
            appended = messages.suffix(from: messages.index(after: index))
        } else {
            // The first live message in a chat that was already loaded empty.
            appended = messages[...]
        }
        return Set(appended.lazy.filter {
            !$0.isSender && !$0.isDeletedMessage
                && $0.numericSortKey > (previous.lastSortKey ?? .min)
        }.map(\.id))
    }
}
