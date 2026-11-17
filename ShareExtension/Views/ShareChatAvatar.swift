import SwiftUI

/// The chat's photo, or its initials while that loads or when there is none.
struct ShareChatAvatar: View {
    let model: ShareModel
    let chat: ShareChat
    @State private var image: CGImage?

    /// The avatar's diameter in points.
    private static let dimension: CGFloat = 40

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
                        // Sized to the circle like Messages: a single
                        // letter at about half the diameter, two a little
                        // smaller. Matches the app's InitialsAvatarView.
                        Text(chat.initials)
                            .font(.system(size: Self.dimension * (chat.initials.count > 1 ? 0.46 : 0.52), design: .rounded))
                            .bold()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, Self.dimension * 0.08)
                    }
            }
        }
        .frame(width: Self.dimension, height: Self.dimension)
        .clipShape(.circle)
        .task(id: chat.avatarURL) {
            image = await model.avatar(for: chat)
        }
    }
}
