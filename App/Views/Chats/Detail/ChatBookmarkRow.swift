import SwiftUI

/// A bookmarked message: who sent it and when, its text, and a thumbnail of
/// its photo or video.
struct ChatBookmarkRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.isSender ? String(localized: "You") : message.senderDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(message.timestamp.chatListText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Group {
                    if message.hasText {
                        Text(message.displayText)
                    } else if let summary = message.attachmentSummary {
                        Label(summary, systemImage: message.attachmentSymbol ?? "paperclip")
                    }
                }
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }

            if let thumbnail {
                ChatMediaThumbnail(source: thumbnail.source, placeholderSymbol: thumbnail.symbol)
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 6))
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    /// The first photo's image or video's poster frame.
    private var thumbnail: (source: String?, symbol: String)? {
        guard let attachment = message.attachments?.first else { return nil }
        switch attachment.type {
        case .image: return (attachment.resolvedURL, "photo")
        case .video, .reel: return (attachment.posterImg, "video")
        default: return nil
        }
    }
}
