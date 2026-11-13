import SwiftUI

/// "+3" after the pills a message shows, opening the sheet of who reacted.
struct ReactionOverflowButton: View {
    @Environment(\.showReactionDetails) private var showReactionDetails
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let hiddenCount: Int
    /// The message the first hidden reaction is on.
    let message: Message
    let chat: Chat

    var body: some View {
        Button {
            showReactionDetails(message, in: chat)
        } label: {
            Text("+\(hiddenCount)")
                // Rolls with the pills' animation; see `ReactionPillsView`.
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(hiddenCount)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .reactionPillChrome(isOwn: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hiddenCount) more reactions")
        .accessibilityHint("Shows everyone's reactions")
    }
}
