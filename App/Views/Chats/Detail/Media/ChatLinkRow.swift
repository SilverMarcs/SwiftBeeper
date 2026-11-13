import SwiftUI

/// A shared link: its site, the address, the message around it, and who
/// shared it when. Tapping opens it.
struct ChatLinkRow: View {
    let link: ChatSharedLink

    var body: some View {
        Link(destination: link.url) {
            HStack(alignment: .top) {
                Image(systemName: "link")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .subtleBackground()
                    .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(link.url.host() ?? link.url.absoluteString)
                        .bold()
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(link.url.absoluteString)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let context = link.context {
                        Text(context)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text(ChatSharedItemCaption.text(for: link.message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            ChatLinkActions(url: link.url)
        }
    }
}
