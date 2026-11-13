import SwiftUI

/// Native macOS palette menus display images, not their items' text titles.
struct ReactionEmojiLabel: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let emoji: String

    var body: some View {
        Label {
            Text(emoji)
        } icon: {
            if let image = emojiImage {
                Image(decorative: image, scale: displayScale)
                    .renderingMode(.original)
            } else {
                Text(emoji)
            }
        }
        .accessibilityLabel(Text(emoji))
    }

    private var emojiImage: CGImage? {
        let renderer = ImageRenderer(content: Text(emoji)
            .font(.title3)
            .environment(\.dynamicTypeSize, dynamicTypeSize))
        renderer.scale = displayScale
        return renderer.cgImage
    }
}
