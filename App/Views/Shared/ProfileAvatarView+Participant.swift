import SwiftUI

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
