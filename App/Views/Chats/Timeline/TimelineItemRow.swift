import SwiftUI

struct TimelineItemRow: View {
    let item: TimelineItem
    let chat: Chat
    let firstUnreadID: String?
    /// The row the timeline focuses on while the composer replies to or
    /// edits its message, or while its quote is shown; every other row
    /// recedes. Nil leaves the timeline as it is.
    let focusedRowID: Message.ID?
    /// A send's caption keeps its layout space while its bubble flies in.
    let hidesDeliveryCaption: Bool
    /// For the reply whose quote was tapped, the messages it shows above
    /// itself.
    let quotedChain: QuotedMessageChainPresentation?
    let quotedFocusRole: QuotedFocusRowRole
    @Environment(\.reactionPicker) private var reactionPicker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var bubbleNamespace
    @State private var hasShownTyping = false

    var body: some View {
        let focusedRowID = effectiveFocusedRowID
        let isIdle = focusedRowID == nil
        ZStack(alignment: .bottomLeading) {
            switch item {
            case .message(let entry, _):
                TimelineEntryRow(
                    entry: entry,
                    chat: chat,
                    showsUnreadDivider: entry.message.id == firstUnreadID,
                    focusedRowID: focusedRowID,
                    quotedChain: quotedChain,
                    quotedFocusRole: quotedFocusRole
                )
                // Reply navigation still addresses the canonical message ID.
                .id(entry.message.id)
                .transition(.opacity)
            case .outgoing(let entry):
                OutgoingTimelineEntryRow(entry: entry, isTimelineIdle: isIdle)
                    .id(entry.id)
            case .deliveryCaption(let indicator):
                DeliveryCaptionView(indicator: indicator, chat: chat)
                    .opacity(hidesDeliveryCaption ? 0 : 1)
                    .timelineFocus(isIdle)
            case .seenCaption(let indicator):
                DeliveryCaptionView(indicator: indicator, chat: chat, isOutgoing: false)
                    .timelineFocus(isIdle)
            case .typing(let bubble, let isFirstInGroup, let joinsAbove):
                TypingIndicatorView(participant: bubble.participant, chat: chat, isFirstInGroup: isFirstInGroup)
                    .environment(\.messageBubbleJoins, joinsAbove ? .above : [])
                    .timelineFocus(isIdle)
                    .timelineRowPadding(startsSenderRun: isFirstInGroup)
                    .transition(.opacity)
            }
        }
        .environment(\.typingBubbleNamespace, item.hasTypingIdentity && !reduceMotion ? bubbleNamespace : nil)
        .environment(\.revealsTypingBubbleContent, hasShownTyping && !reduceMotion)
        .onAppear {
            // History rows don't replay the handoff when scrolled back into view.
            if case .typing = item { hasShownTyping = true }
        }
    }

    /// The timeline's focus, or else the message an emoji is being picked
    /// for, which focuses like a reply's target.
    private var effectiveFocusedRowID: Message.ID? {
        if let focusedRowID { return focusedRowID }
        guard let reactionPicker, reactionPicker.isChoosing else { return nil }
        if case .message(let entry, _) = item, entry.messages.contains(where: { $0.id == reactionPicker.id }) {
            return entry.id
        }
        return reactionPicker.id
    }
}
