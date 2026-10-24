import SwiftUI

/// Two to four member avatars arranged inside one circle.
struct GroupChatAvatarView: View {
    let title: String
    let participants: [ChatParticipant]
    let dimension: CGFloat

    /// Each avatar's size and center offset as fractions of `dimension`,
    /// indexed by avatar count minus two.
    private static let layouts: [[(size: CGFloat, x: CGFloat, y: CGFloat)]] = [
        [(0.56, -0.16, -0.08), (0.56, 0.16, 0.12)],
        [(0.46, -0.17, -0.16), (0.42, 0.18, -0.04), (0.44, -0.02, 0.2)],
        [(0.4, -0.18, -0.16), (0.38, 0.19, -0.08), (0.38, -0.16, 0.18), (0.36, 0.17, 0.2)],
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
                    imageURLString: avatars[index].imageURL,
                    dimension: dimension * slot.size
                )
                .offset(x: dimension * slot.x, y: dimension * slot.y)
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(.circle)
    }

    /// Up to four members, padded with initials-only avatars to at least two.
    private var avatars: [(name: String, imageURL: String?)] {
        let members = participants.prefix(4).map { (name: $0.displayName, imageURL: $0.imgURL) }
        switch members.count {
        case 0: return [(title, nil), ("Group", nil)]
        case 1: return [members[0], (title, nil)]
        default: return members
        }
    }
}
