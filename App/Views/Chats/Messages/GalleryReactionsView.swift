import SwiftUI

/// Every photo's reactions in a gallery, side by side on its last bubble.
struct GalleryReactionsView: View {
    let messages: [Message]
    let chat: Chat

    var body: some View {
        HStack(spacing: 4) {
            ForEach(messages) { message in
                ReactionsBarView(message: message, chat: chat)
            }
        }
    }
}
