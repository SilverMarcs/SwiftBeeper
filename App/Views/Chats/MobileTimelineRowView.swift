#if os(iOS)
import SwiftUI

struct MobileTimelineRowView: View {
    let row: MobileTimelineRow
    let onTapLinkedMessage: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch row.content {
            case let .message(message, showsTimestamp, isFirstInGroup, isLastInGroup, linkedMessage):
                if row.showsUnreadDivider {
                    UnreadDividerView()
                        .padding(.vertical, 2)
                }
                if showsTimestamp {
                    TimestampDividerView(timestamp: message.timestamp)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                MessageRowView(
                    message: message,
                    chat: row.chat,
                    showReadIndicator: row.showsReadIndicator,
                    isFirstInGroup: isFirstInGroup,
                    isLastInGroup: isLastInGroup,
                    linkedMessage: linkedMessage,
                    onTapLinkedMessage: onTapLinkedMessage
                )
            case let .outgoing(message, showsTimestamp, linkedMessage):
                if showsTimestamp {
                    TimestampDividerView(timestamp: message.createdAt)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                OutgoingMessageRowView(
                    message: message,
                    linkedMessage: linkedMessage,
                    onTapLinkedMessage: onTapLinkedMessage
                )
            case .loadingOlder:
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(TimelineFocusEffect(isFocused: row.isFocused))
        .accessibilityElement(children: .contain)
    }
}
#endif
