import SwiftUI

struct WatchChatAvatarView: View {
    let title: String
    let imageURL: String?
    let dimension: CGFloat

    var body: some View {
        AsyncImage(url: imageURL.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Text(initials)
                            .bold()
                            .foregroundStyle(.primary)
                    }
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(.circle)
        .accessibilityLabel(title)
    }

    private var initials: String {
        let characters = title
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        return characters.isEmpty ? "?" : String(characters)
    }
}
