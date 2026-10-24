import SwiftUI

/// A canonical message with the dividers above it. While the composer replies
/// to or edits a message, everything else recedes.
struct TimelineEntryRow: View {
    let entry: TimelineEntry
    let chat: Chat
    let showsUnreadDivider: Bool
    let activeComposerMessageID: Message.ID?

    var body: some View {
        let isComposerIdle = activeComposerMessageID == nil
        VStack(spacing: 0) {
            if showsUnreadDivider {
                UnreadDividerView()
                    .timelineFocus(isComposerIdle)
                    .padding(.vertical, 4)
            }

            if entry.showsTimestamp {
                TimestampDividerView(timestamp: entry.message.timestamp)
                    .timelineFocus(isComposerIdle)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            MessageRowView(entry: entry, chat: chat)
                .timelineFocus(isComposerIdle || activeComposerMessageID == entry.message.id)
                .padding(.vertical, 2)
        }
    }
}
