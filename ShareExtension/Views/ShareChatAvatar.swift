import SwiftUI

/// The chat's photo, or its initials while that loads or when there is none.
struct ShareChatAvatar: View {
    let model: ShareModel
    let chat: ShareChat
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Text(chat.initials)
                            .font(.caption)
                            .bold()
                    }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(.circle)
        .task(id: chat.avatarURL) {
            image = await model.avatar(for: chat)
        }
    }
}
