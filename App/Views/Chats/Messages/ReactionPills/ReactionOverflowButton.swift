import SwiftUI

/// "+3" after the pills a message shows, opening the sheet of who reacted.
struct ReactionOverflowButton: View {
    @Environment(\.showReactionDetails) private var showReactionDetails

    let hiddenCount: Int
    /// The message the first hidden reaction is on.
    let message: Message
    let chat: Chat

    var body: some View {
        Button {
            showReactionDetails(message, in: chat)
        } label: {
            Text("+\(hiddenCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background { ReactionPillFill(isOwn: false) }
                .clipShape(.capsule)
                        .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hiddenCount) more reactions")
        .accessibilityHint("Shows everyone's reactions")
    }
}
