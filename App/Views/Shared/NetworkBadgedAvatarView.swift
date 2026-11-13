import SwiftUI

/// A chat's avatar with its network's logo, or its Slack workspace's icon,
/// in the bottom trailing corner. The avatar is cut away around the badge,
/// so the gap shows whatever is behind the row, selected or not. Without a
/// badge image it's the plain avatar.
struct NetworkBadgedAvatarView: View {
    let chat: Chat
    let dimension: CGFloat
    let networkImageURL: String?

    var body: some View {
        if let networkImageURL {
            let badge = dimension * 0.3
            let gap = dimension * 0.04
            let cutout = badge + gap * 2
            ChatAvatarView(chat: chat, dimension: dimension)
                .mask {
                    Rectangle()
                        .overlay(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: cutout * NetworkBadgeView.cornerFraction)
                                .frame(width: cutout, height: cutout)
                                .offset(x: gap, y: gap)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .overlay(alignment: .bottomTrailing) {
                    NetworkBadgeView(imageURL: networkImageURL, dimension: badge)
                }
        } else {
            ChatAvatarView(chat: chat, dimension: dimension)
        }
    }
}
