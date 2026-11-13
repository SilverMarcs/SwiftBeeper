import SwiftUI

/// One reaction pill. A tap reacts the same way, or takes the user's
/// reaction back; holding it opens the sheet of who reacted.
struct ReactionPillButton: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.showReactionDetails) private var showReactionDetails

    let pill: ReactionPill
    let chat: Chat

    /// Set when a hold opened the sheet, so the release that follows it
    /// doesn't also toggle the reaction.
    @State private var didLongPress = false
    @State private var longPressCount = 0

    var body: some View {
        Button(action: toggle) {
            ReactionPillLabel(pill: pill, chat: chat)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture().onEnded { _ in
                didLongPress = true
                longPressCount += 1
                showReactionDetails(pill.message, in: chat)
            }
        )
        .sensoryFeedback(.impact, trigger: longPressCount)
        .accessibilityAddTraits(pill.isOwn ? .isSelected : [])
        .accessibilityHint(pill.isOwn ? "Removes your reaction" : "Reacts with \(pill.group.reactionKey)")
        .accessibilityAction(named: "Show Reactions") {
            showReactionDetails(pill.message, in: chat)
        }
        .help("Hold to see who reacted")
    }

    private func toggle() {
        guard !didLongPress else {
            didLongPress = false
            return
        }
        let message = pill.message
        let reactionKey = pill.group.reactionKey
        Task {
            if pill.isOwn {
                await chatStore.removeReaction(from: message.id, in: message.chatID, reactionKey: reactionKey)
            } else {
                await chatStore.addReaction(to: message.id, in: message.chatID, reactionKey: reactionKey)
            }
        }
    }
}
