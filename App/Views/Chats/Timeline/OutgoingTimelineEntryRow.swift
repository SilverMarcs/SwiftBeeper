import SwiftUI

/// An optimistic message with its timestamp divider. It is never a composer
/// target, so only the divider recedes while the composer is focused on a message.
struct OutgoingTimelineEntryRow: View {
    let entry: OutgoingTimelineEntry
    let activeComposerMessageID: Message.ID?

    var body: some View {
        VStack(spacing: 0) {
            if entry.showsTimestamp {
                TimestampDividerView(timestamp: entry.message.createdAt)
                    .timelineFocus(activeComposerMessageID == nil)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            OutgoingMessageRowView(entry: entry)
                .padding(.vertical, 2)
        }
    }
}
