import SwiftUI

/// The footer under a thread root, like Slack's: who replied and how many
/// replies. Tapping it opens the thread; its context menu marks it as read.
struct ThreadSummaryButton: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let message: Message
    let summary: ThreadSummary
    let chat: Chat

    var body: some View {
        let isUnread = chatStore.isThreadUnread(message)
        Button {
            chatStore.showThread(for: message)
        } label: {
            HStack(spacing: 6) {
                ThreadParticipantsView(participants: (summary.participants ?? []).map {
                    chatStore.displayedParticipant($0, in: chat)
                })

                Text("^[\(summary.replyCount) reply](inflect: true)")
                    .bold()
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(summary.replyCount)))
                    .foregroundStyle(.secondary)

                if isUnread {
                    // The chat list's unread dot.
                    Image(systemName: "circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Unread")
                }

                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
            }
            .chatFont(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // The neutral bubble fill on both sides, so the secondary text
            // reads the same under outgoing roots as incoming ones.
            .subtleBackground()
            .clipShape(.capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open Thread", systemImage: "bubble.left.and.text.bubble.right") {
                chatStore.showThread(for: message)
            }
            if isUnread {
                ThreadMarkAsReadButton(rootID: message.id, chatID: message.chatID)
            }
        }
        // Scoped to the footer, so its capsule resizes with the count while
        // the row around it stays put.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: summary.replyCount)
        .accessibilityHint("Opens the thread")
    }
}
