import SwiftUI

/// Who has seen a group message: a capsule of their overlapping avatars,
/// the first few of them, then how many more.
struct SeenByPillView: View {
    let readers: [ChatParticipant]
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

    /// The chat's loaded participant when the sample has them, otherwise
    /// the profile their receipt carries, as for a message's sender.
    private func participant(for reader: ChatParticipant) -> ChatParticipant {
        chat.participant(with: reader.id) ?? reader
    }
}
