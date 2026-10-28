import SwiftUI

struct TimelineItemRow: View {
    let item: TimelineItem
    let chat: Chat
    let firstUnreadID: String?
    let activeComposerMessageID: Message.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var bubbleNamespace
    @State private var hasShownTyping = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            switch item {
            case .message(let entry, _):
                TimelineEntryRow(
                    entry: entry,
                    chat: chat,
                    showsUnreadDivider: entry.message.id == firstUnreadID,
                    activeComposerMessageID: activeComposerMessageID
                )
                // Reply navigation still addresses the canonical message ID.
                .id(entry.message.id)
                .transition(.opacity)
            case .outgoing(let entry):
                OutgoingTimelineEntryRow(entry: entry, activeComposerMessageID: activeComposerMessageID)
                    .id(entry.id)
            case .typing(let bubble, let isFirstInGroup):
                TypingIndicatorView(participant: bubble.participant, chat: chat, isFirstInGroup: isFirstInGroup)
                    .timelineFocus(activeComposerMessageID == nil)
                    .padding(.vertical, 2)
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
}
