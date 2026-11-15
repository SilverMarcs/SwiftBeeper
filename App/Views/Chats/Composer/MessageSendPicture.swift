import CoreGraphics

/// Text drawn once for a flight, which then only moves.
struct MessageSendPicture {
    let image: CGImage
    /// Where it was drawn, in points; global for the composer's text.
    let frame: CGRect

    /// Pixels per point.
    var scale: CGFloat {
        frame.width > 0 ? CGFloat(image.width) / frame.width : 1
    }
}
