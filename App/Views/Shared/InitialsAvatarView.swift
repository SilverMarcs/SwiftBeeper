import SwiftUI

/// The first letters of up to two words of a name, or "?" for an empty name,
/// in white on the person's own colour.
///
/// The monogram scales with the circle like Messages' contact avatars:
/// rounded bold letters, a single letter at about half the diameter and two
/// letters a little smaller so they still sit comfortably inside.
struct InitialsAvatarView: View {
    let name: String
    /// The stable ID whose hash picks the colour: a Matrix user ID, or a
    /// chat ID for a chat's own initials. See `IdentityColor`.
    let colorID: String
    /// The circle's diameter in points, which sizes the letters.
    let dimension: CGFloat

    /// Font size as a fraction of the diameter, measured from Messages.
    private static let singleLetterScale: CGFloat = 0.52
    private static let twoLetterScale: CGFloat = 0.46

    var body: some View {
        let initials = self.initials
        Circle()
            .fill(IdentityColor(id: colorID).avatarGradient)
            .overlay {
                // The monogram is part of the artwork, so it follows the
                // circle rather than Dynamic Type.
                Text(initials)
                    .font(.system(size: fontSize(for: initials), design: .rounded))
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, dimension * 0.08)
            }
    }

    private var initials: String {
        let letters = name.trimmed.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    private func fontSize(for initials: String) -> CGFloat {
        dimension * (initials.count > 1 ? Self.twoLetterScale : Self.singleLetterScale)
    }
}
