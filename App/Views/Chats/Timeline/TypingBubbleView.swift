import SwiftUI

/// The animated dots in an incoming bubble, as the timeline's typing row shows them.
struct TypingBubbleView: View {
    var body: some View {
        TypingDotsView()
            .messageBubbleChrome(isOutgoing: false)
    }
}
