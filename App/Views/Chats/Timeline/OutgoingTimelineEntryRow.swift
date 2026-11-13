import SwiftUI

/// An optimistic message with its timestamp divider. It is never a composer
/// target, so only the divider recedes while the timeline focuses on a message.
struct OutgoingTimelineEntryRow: View {
    let entry: OutgoingTimelineEntry
    /// False while the timeline focuses on a message.
    let isTimelineIdle: Bool

    var body: some View {
        VStack(spacing: 0) {
            if entry.showsTimestamp {
                TimestampDividerView(timestamp: entry.message.createdAt)
                    .timelineFocus(isTimelineIdle)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            OutgoingMessageRowView(entry: entry)
                .timelineRowPadding(startsSenderRun: entry.startsSenderRun)
        }
    }
}
