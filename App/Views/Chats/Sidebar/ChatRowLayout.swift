import SwiftUI

/// The layout every chat list row shares, for chats and message search
/// results alike: the avatar, then the bold name and time over two reserved
/// lines of preview with optional badges beside them.
struct ChatRowLayout<Preview: View, Badges: View>: View {
    /// The chat whose avatar leads the row; nil leaves the avatar out.
    let chat: Chat?
    /// The logo badging the avatar; nil shows the plain avatar.
    let networkImageURL: String?
    let title: String
    var isPinned = false
    let timeText: String?
    @ViewBuilder let preview: Preview
    @ViewBuilder let badges: Badges

    var body: some View {
        HStack(spacing: Self.avatarSpacing) {
            if let chat {
                NetworkBadgedAvatarView(chat: chat, dimension: Self.avatarDimension, networkImageURL: networkImageURL)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }

                    Spacer()

                    if let timeText {
                        Text(timeText)
                            #if os(macOS)
                            .font(.callout)
                            #else
                            .font(.subheadline)
                            #endif
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    preview
                        #if os(macOS)
                        .font(.body)
                        #else
                        .font(.subheadline)
                        #endif
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)

                    Spacer()

                    badges
                }
            }
        }
        #if os(macOS)
        .padding(.horizontal, 5)
        .padding(.vertical, 9)
        #else
        .padding(-1)
        #endif
    }

    // Computed, since generic types can't store statics.
    #if os(macOS)
    private static var avatarDimension: CGFloat { 43 }
    private static var avatarSpacing: CGFloat { 8 }
    #else
    private static var avatarDimension: CGFloat { 48 }
    private static var avatarSpacing: CGFloat { 12 }
    #endif
}
