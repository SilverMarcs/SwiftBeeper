import SwiftUI

/// Two to five member avatars of varying sizes floating inside one circle,
/// with the first member largest at the top left.
struct GroupChatAvatarView: View {
    let title: String
    /// Colours the title's initials when they stand in for a member.
    let chatID: String
    let participants: [ChatParticipant]
    let dimension: CGFloat

    /// The most member avatars the collage shows.
    private static let maximumAvatarCount = 5

    /// Each avatar's size and center offset as fractions of `dimension`,
    /// indexed by avatar count minus two. Every bubble sits fully inside the
    /// circle with a small gap between neighbours.
    private static let layouts: [[(size: CGFloat, x: CGFloat, y: CGFloat)]] = [
        [(0.5, -0.13, -0.11), (0.36, 0.2, 0.2)],
        [(0.5, -0.13, -0.13), (0.36, 0.24, 0.14), (0.28, -0.12, 0.27)],
        [(0.48, -0.14, -0.14), (0.36, 0.25, 0.08), (0.32, -0.08, 0.26), (0.22, 0.22, -0.26)],
        [(0.48, -0.145, -0.145), (0.22, 0.24, -0.25), (0.345, 0.25, 0.075), (0.26, -0.06, 0.27), (0.16, -0.305, 0.205)],
    ]

    var body: some View {
        let avatars = self.avatars
        let layout = Self.layouts[avatars.count - 2]
        ZStack {
            Circle()
                .fill(.quinary)

            ForEach(layout.indices, id: \.self) { index in
                let slot = layout[index]
                ProfileAvatarView(
                    name: avatars[index].name,
                    colorID: avatars[index].colorID,
                    imageURLString: avatars[index].imageURL,
                    dimension: dimension * slot.size
                )
                .offset(x: dimension * slot.x, y: dimension * slot.y)
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(.circle)
    }

    /// Up to five members, padded with initials-only avatars to at least two.
    private var avatars: [(name: String, colorID: String, imageURL: String?)] {
        let members = participants.prefix(Self.maximumAvatarCount).map { (name: $0.displayName, colorID: $0.id, imageURL: $0.imgURL) }
        switch members.count {
        case 0: return [(title, chatID, nil), ("Group", "Group", nil)]
        case 1: return [members[0], (title, chatID, nil)]
        default: return members
        }
    }
}
