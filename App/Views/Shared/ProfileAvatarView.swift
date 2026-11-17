import SwiftMediaViewer
import SwiftUI

/// A circular photo, or the name's initials on the person's own colour
/// while it loads or when there is none.
struct ProfileAvatarView: View {
    let name: String
    /// The stable ID that colours the initials: a Matrix user ID, or a chat
    /// ID for a chat's own initials. See `IdentityColor`.
    let colorID: String
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
                    InitialsAvatarView(name: name, colorID: colorID, dimension: dimension)
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
            colorID: participant?.id ?? "?",
            imageURLString: participant?.imgURL,
            dimension: dimension,
            allowsFullscreen: allowsFullscreen
        )
    }
}

#Preview {
    ProfileAvatarView(name: "Alice Wonder", colorID: "@alice:example.org", imageURLString: nil, dimension: 36)
}
