import CoreGraphics

/// The composer as it was the moment a draft was sent: the field the bubble
/// grows out of, and the text as the reader saw it there. All in SwiftUI's
/// global space.
struct MessageSendSource {
    /// The field the draft was typed in, which turns into the bubble.
    let fieldFrame: CGRect
    let fieldCornerRadius: CGFloat
    /// Where the bubble's text lines up with the composer's: the leading
    /// edge of the draft's first line, or, for a draft scrolled down, of its
    /// last line's bottom, so the lines the reader saw stay in place and the
    /// rest come into view around them.
    let textAnchor: CGPoint
    /// Whether `textAnchor` is the last line's bottom.
    let anchorsLastLine: Bool
    /// The draft's visible characters where the editor drew them, where
    /// the bubble's glyphs start from.
    let glyphs: [MessageSendSourceGlyph]

    /// The most characters a send records; past a full field there's
    /// nothing more to see.
    static let maximumGlyphs = 800
}
