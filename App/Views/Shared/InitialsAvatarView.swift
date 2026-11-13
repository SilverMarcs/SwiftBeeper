import SwiftUI

/// The first letters of up to two words of a name, or "?" for an empty name,
/// in white on the person's own colour.
struct InitialsAvatarView: View {
    let name: String
    /// The stable ID whose hash picks the colour: a Matrix user ID, or a
    /// chat ID for a chat's own initials. See `IdentityColor`.
    let colorID: String

    var body: some View {
        Circle()
            .fill(IdentityColor(id: colorID).avatarGradient)
            .overlay {
                Text(initials)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
            }
    }

    private var initials: String {
        let letters = name.trimmed.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
