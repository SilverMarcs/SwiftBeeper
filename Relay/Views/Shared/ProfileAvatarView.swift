import SwiftMediaViewer
import SwiftUI

struct ProfileAvatarView: View {
    let name: String
    let imageURLString: String?
    let dimension: CGFloat
    var allowsFullscreen: Bool = false

    var body: some View {
        Group {
            if allowsFullscreen, let displayURL = AuthenticatedImageLoader.displayURL(for: imageURLString) {
                SMVImage(url: displayURL, targetSize: targetSize)
            } else {
                CachedAsyncImage(
                    url: AuthenticatedImageLoader.displayURL(for: imageURLString),
                    targetSize: targetSize
                ) {
                    initialsAvatar
                }
            }
        }
        .scaledToFill()
        .frame(width: dimension, height: dimension)
        .clipShape(.circle)
    }

    /// Decode size in pixels — 3x the point dimension covers Retina displays.
    private var targetSize: Int {
        Int(dimension * 3)
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
}
