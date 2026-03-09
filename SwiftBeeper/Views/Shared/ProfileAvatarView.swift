import SwiftUI

struct ProfileAvatarView: View {
    @Environment(SessionStore.self) private var sessionStore

    let name: String
    let imageURLString: String?
    let dimension: CGFloat
    @State private var loadedImage: Image?

    var body: some View {
        Group {
            if let loadedImage {
                loadedImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: dimension, height: dimension)
                    .clipShape(.circle)
            } else {
                initialsAvatar
            }
        }
        .task(id: imageRequestKey) {
            await loadImage()
        }
    }

    private var imageRequestKey: String {
        "\(imageURLString ?? "none")|\(sessionStore.accessToken)"
    }

    private func loadImage() async {
        guard let imageURLString, !imageURLString.isEmpty else {
            loadedImage = nil
            return
        }

        loadedImage = await AuthenticatedImageLoader.loadImage(
            urlString: imageURLString,
            accessToken: sessionStore.accessToken
        )
    }

    private var initialsAvatar: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(initials)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.primary)
            }
            .frame(width: dimension, height: dimension)
    }

    private var initials: String {
        let words = name
            .trimmed
            .split(separator: " ")

        let pickedCharacters = words.prefix(2).compactMap { word in
            word.first.map(String.init)
        }

        if pickedCharacters.isEmpty {
            return "?"
        }

        return pickedCharacters.joined()
    }
}

#Preview {
    ProfileAvatarView(name: "Alice Wonder", imageURLString: nil, dimension: 36)
        .environment(SessionStore())
}
