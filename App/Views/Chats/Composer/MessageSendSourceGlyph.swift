import CoreGraphics

/// One character the composer showed, where it drew it.
struct MessageSendSourceGlyph {
    /// Its UTF-16 offset in the sent text, which leaves out the draft's
    /// leading whitespace.
    let offset: Int
    /// In SwiftUI's global space.
    let frame: CGRect
}
