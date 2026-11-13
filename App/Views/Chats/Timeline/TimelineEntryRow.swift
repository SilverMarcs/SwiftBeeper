import SwiftUI

/// A canonical message with the dividers above it. While the timeline focuses
/// on one message, for a reply, an edit, a reaction or a quote, everything
/// else recedes.
struct TimelineEntryRow: View {
    let entry: TimelineEntry
    let chat: Chat
    let showsUnreadDivider: Bool
    let focusedRowID: Message.ID?
    /// The messages this reply quotes, floated above it while its quote is
    /// shown. Empty otherwise.
    let quotedChain: [TimelineEntry]

    var body: some View {
        let isIdle = focusedRowID == nil
        VStack(spacing: 0) {
            if showsUnreadDivider {
                UnreadDividerView()
                    .timelineFocus(isIdle)
                    .padding(.vertical, 4)
            }

            if entry.showsTimestamp {
                TimestampDividerView(timestamp: entry.message.timestamp)
                    .timelineFocus(isIdle)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            MessageRowView(entry: entry, chat: chat)
                .timelineFocus(isIdle || focusedRowID == entry.id)
                .timelineRowPadding(startsSenderRun: entry.startsSenderRun)
                // The dividers above stay put while the message slides.
                .messageSwipeActions(entry.message, in: chat, isEnabled: isIdle)
                // Over the receded rows above, so the reply keeps its place.
                .overlay(alignment: .top) {
                    if !quotedChain.isEmpty {
                        QuotedMessageChainView(entries: quotedChain, chat: chat)
                            .fixedSize(horizontal: false, vertical: true)
                            .alignmentGuide(.top) { $0[.bottom] }
                            .transition(.opacity)
                    }
                }
        }
    }
}
