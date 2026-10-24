import SwiftUI

/// A sending message's attachment, previewed from the picked data.
struct OutgoingAttachmentView: View {
    let attachment: PendingAttachment
    let message: OutgoingMessage

    var body: some View {
        Group {
            if let decoded = attachment.decodedImage() {
                let size = MediaBubbleSize.fitting(decoded.size)
                decoded.image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .subtleBackground()
            } else {
                HStack {
                    Image(systemName: attachment.symbolName)
                        .font(.title)

                    Text(attachment.fileName)
                        .font(.callout)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: 275, minHeight: 64)
                .bubbleBackground(isOutgoing: true)
            }
        }
        .overlay {
            switch message.state {
            case .sending:
                ZStack {
                    Color.black.opacity(0.18)
                    ProgressView()
                        .tint(.white)
                }
            case .failed:
                Color.black.opacity(0.12)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}
