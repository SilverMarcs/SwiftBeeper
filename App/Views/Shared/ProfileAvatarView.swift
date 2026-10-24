import SwiftMediaViewer
import SwiftUI

/// A circular photo, or the name's initials while it loads or when there is none.
struct ProfileAvatarView: View {
    let name: String
    let imageURLString: String?
    let dimension: CGFloat
    var allowsFullscreen: Bool = false

    var body: some View {
        let displayURL = MatrixMedia.displayURL(for: imageURLString)
        Group {
            if allowsFullscreen, let displayURL {
                SMVImage(url: displayURL, targetSize: targetSize)
            } else {
                CachedAsyncImage(url: displayURL, targetSize: targetSize) {
                    InitialsAvatarView(name: name)
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
}

extension ProfileAvatarView {
    /// A participant's photo, or their initials. A missing participant shows "?".
    init(participant: ChatParticipant?, dimension: CGFloat, allowsFullscreen: Bool = false) {
        self.init(
            name: participant?.displayName ?? "?",
            imageURLString: participant?.imgURL,
            dimension: dimension,
            allowsFullscreen: allowsFullscreen
        )
    }
}

#Preview {
    ProfileAvatarView(name: "Alice Wonder", imageURLString: nil, dimension: 36)
}
