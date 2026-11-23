import SwiftUI

/// A reaction as drawn: its emoji, a custom emoji's image at the emoji's
/// size in the surrounding text, or a dashed face for one Relay can't draw.
struct ReactionGlyph: View {
    let appearance: ReactionAppearance
    /// Whether it sits on the accent fill of the user's own reaction.
    var isOnAccent = false

    @ScaledMetric private var imageDimension: CGFloat

    /// `textStyle` is the surrounding font's, which a custom emoji's image
    /// is sized and scaled with.
    init(_ appearance: ReactionAppearance, textStyle: Font.TextStyle, isOnAccent: Bool = false) {
        self.appearance = appearance
        self.isOnAccent = isOnAccent
        _imageDimension = ScaledMetric(wrappedValue: Self.imageDimension(for: textStyle), relativeTo: textStyle)
    }

    var body: some View {
        switch appearance {
        case .emoji(let emoji):
            Text(emoji)
        case .customEmoji(let source):
            CustomEmojiImage(source: source, dimension: imageDimension)
        case .unrecognized:
            Image(systemName: "face.dashed")
                .foregroundStyle(isOnAccent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
    }

    /// About the height of an emoji in the style at the default text size.
    static func imageDimension(for textStyle: Font.TextStyle) -> CGFloat {
        switch textStyle {
        case .subheadline: 18
        case .title2: 26
        default: 20
        }
    }
}
