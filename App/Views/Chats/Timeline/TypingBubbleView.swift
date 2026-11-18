import SwiftUI

/// The animated dots in an incoming bubble: the timeline's typing row and a
/// chat list row's preview both show this.
struct TypingBubbleView: View {
    var body: some View {
        TypingDotsView()
            // The dots hold one line of message text, even under a chat row's
            // reserved preview lines.
            .lineLimit(1, reservesSpace: false)
            .messageBubbleChrome(isOutgoing: false)
    }
}
