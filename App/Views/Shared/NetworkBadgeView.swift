import SwiftMediaViewer
import SwiftUI

/// A network's logo or a workspace's icon as a small rounded square, for
/// the corner of an avatar. Logos without a background of their own, such as Slack's, sit on white.
struct NetworkBadgeView: View {
    let imageURL: String
    let dimension: CGFloat

    var body: some View {
        CachedAsyncImage(url: MatrixMedia.displayURL(for: imageURL), targetSize: Int(dimension * 3)) {
            Color.clear
        }
        .scaledToFit()
        .frame(width: dimension, height: dimension)
        .background(.white)
        .clipShape(.rect(cornerRadius: dimension * Self.cornerFraction))
        .accessibilityHidden(true)
    }

    /// The corner radius as a fraction of the badge's side.
    static let cornerFraction: CGFloat = 0.28
}
