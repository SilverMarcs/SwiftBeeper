import SwiftUI

/// Who has seen a group message: a capsule of their overlapping avatars,
/// the first few of them, then how many more.
struct SeenByPillView: View {
    let readers: [DeliveryReader]
    let chat: Chat

    /// Grows with the caption text it stands in for.
    @ScaledMetric(relativeTo: .caption2) private var dimension: CGFloat = 16
    private static let shownLimit = 4

    var body: some View {
        HStack(spacing: 3) {
            OverlappingAvatarsView(
                participants: readers.prefix(Self.shownLimit).map(participant(for:)),
                dimension: dimension
            ) {
                Color.clear.subtleBackground()
            }

            if readers.count > Self.shownLimit {
                Text("+\(readers.count - Self.shownLimit)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
        }
        .padding(1)
        .background { Color.clear.subtleBackground() }
        .clipShape(.capsule)
    }

    /// The reader's profile, for their photo, or their receipt's name when
    /// the chat hasn't loaded them.
    private func participant(for reader: DeliveryReader) -> ChatParticipant {
        chat.participant(with: reader.id)
            ?? ChatParticipant(id: reader.id, username: nil, fullName: reader.name, imgURL: nil, isSelf: false)
    }
}
