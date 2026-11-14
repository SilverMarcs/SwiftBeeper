import Foundation

/// In a group, the sender's name or avatar a tapped quote's reply takes from
/// its run of messages: the name from the run's first row, to stand between
/// the chain and the reply's bubble, and the avatar from its last row, to
/// sit beside the reply.
struct QuotedSenderHandoff: Equatable {
    /// The row the name or avatar comes from, which may be the reply's own.
    let rowID: Message.ID
    /// Where it ended in the timeline content's space, for a row on screen.
    /// It moves from there; nil fades it in instead.
    let origin: CGFloat?

    /// The name and avatar the reply in `replyRowID` takes. Nil for the
    /// user's own messages and direct chats, which show neither, and for an
    /// avatar the reply already has. `frames` is nil to fade both in.
    @MainActor
    static func handoffs(
        for replyRowID: Message.ID,
        in timeline: [TimelineEntry],
        chat: Chat,
        frames: TimelineRowFrames?
    ) -> (name: QuotedSenderHandoff?, avatar: QuotedSenderHandoff?) {
        guard !chat.isSingleChat, let index = timeline.firstIndex(where: { $0.id == replyRowID }),
              !timeline[index].message.isSender else { return (nil, nil) }

        var first = index
        while first > timeline.startIndex, !timeline[first].isFirstInGroup {
            first = timeline.index(before: first)
        }
        let nameRowID = timeline[first].id
        let name = QuotedSenderHandoff(rowID: nameRowID, origin: frames?.senderNameBottom(of: nameRowID))

        guard !timeline[index].isLastInGroup else { return (name, nil) }
        var last = index
        while last < timeline.index(before: timeline.endIndex), !timeline[last].isLastInGroup {
            last = timeline.index(after: last)
        }
        let avatarRowID = timeline[last].id
        let avatar = QuotedSenderHandoff(rowID: avatarRowID, origin: frames?.senderAvatarBottom(of: avatarRowID))
        return (name, avatar)
    }
}
