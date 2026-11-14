import SwiftUI

/// One glyph of a reflowing sent message.
struct MessageSendReflowGlyph {
    let slice: Text.Layout.RunSlice
    /// Where the composer drew it, from its place in the bubble, beyond
    /// the text as a whole moves: the difference the composer's lines make.
    /// Nil for a glyph the composer didn't show, which appears with the
    /// bubble's lines.
    let start: CGSize?
}
