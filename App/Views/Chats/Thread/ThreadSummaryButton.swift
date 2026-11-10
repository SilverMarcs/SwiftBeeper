import SwiftUI

/// The footer under a thread root, like Slack's: who replied and how many
/// replies. Tapping it opens the thread.
struct ThreadSummaryButton: View {
    @Environment(ChatStore.self) private var chatStore

    let message: Message
    let summary: ThreadSummary
    let chat: Chat

    var body: some View {
        Button {
            chatStore.showThread(for: message)
        } label: {
            HStack(spacing: 6) {
                ThreadParticipantsView(participants: (summary.participants ?? []).map {
                    chatStore.displayedParticipant($0, in: chat)
                })

                Text("^[\(summary.replyCount) reply](inflect: true)")
                    .bold()
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // The same fill as the message's own bubble.
            .bubbleBackground(isOutgoing: message.isSender)
            .clipShape(.capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the thread")
    }
}
