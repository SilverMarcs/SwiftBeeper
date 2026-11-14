import SwiftUI

/// The composer's lines for a sent message, drawn with the bubble's glyphs.
///
/// The composer is narrower than a bubble, so a longer message wraps
/// differently in each. The flying text keeps each glyph where the composer
/// drew it, relative to the text's anchor, until it takes the bubble's own
/// lines mid-flight. Glyphs the composer didn't show appear with them.
///
/// Glyphs are matched to characters by their offset, which only holds while
/// the bubble shows the text exactly as sent; formatted text, which
/// Markdown has changed, lands without reflowing.
struct MessageSendReflow {
    let glyphs: [MessageSendReflowGlyph]

    /// Nil when there's nothing to reflow: the text wraps the same in both,
    /// or the bubble's text can't be matched to the composer's.
    /// - Parameters:
    ///   - layouts: The bubble's text layouts.
    ///   - textLength: The sent text's length in UTF-16 units.
    ///   - anchor: The point of the bubble's text that lines up with the
    ///     source's `textAnchor`, in the text's own space.
    init?(layouts: [Text.Layout], textLength: Int, source: MessageSendSource, anchor: CGPoint) {
        guard layouts.count == 1, let layout = layouts.first, !source.glyphs.isEmpty else { return nil }
        let slices = layout.flatMap { line in line.flatMap { run in run.indices.map { run[$0] } } }
        let indices = slices.compactMap(\.characterIndices.first)
        guard let base = indices.min(), let last = indices.max(),
              // Markdown that removed characters leaves the offsets apart.
              abs(base.distance(to: last) - (textLength - 1)) <= 4 else { return nil }

        let sourceFrames = Dictionary(source.glyphs.map { ($0.offset, $0.frame) }) { first, _ in first }
        var moves = false
        glyphs = slices.map { slice in
            let bounds = slice.typographicBounds.rect
            var start: CGSize?
            if let index = slice.characterIndices.first, let frame = sourceFrames[base.distance(to: index)] {
                let offset = CGSize(
                    width: (frame.minX - source.textAnchor.x) - (bounds.minX - anchor.x),
                    height: (frame.midY - source.textAnchor.y) - (bounds.midY - anchor.y)
                )
                if abs(offset.width) > 0.5 || abs(offset.height) > 0.5 { moves = true }
                start = offset
            }
            return MessageSendReflowGlyph(slice: slice, start: start)
        }
        guard moves else { return nil }
    }
}
