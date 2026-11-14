import SwiftUI

/// Where everything in a flight is at one moment, in the flight layer.
///
/// The composer's field turns into the bubble at once, the size and shape
/// of it, then narrows and rises into the bubble. Its text moves as one
/// block, starting exactly on the composer's text; the fill is a window onto
/// it, so lines the field had scrolled away or cut off come into view as the
/// fill grows into the bubble.
struct MessageSendFrame {
    /// The fill's frame.
    let fill: CGRect
    let cornerRadii: RectangleCornerRadii
    /// How far the bubble's text is from where it lands.
    let textOffset: CGSize
    /// Whether the text has left the composer's lines for the bubble's. See
    /// `MessageSendReflow`.
    let hasReflowed: Bool

    /// - Parameters:
    ///   - bubble: The real bubble's frame, in the layer.
    ///   - bubbleText: The point of the real bubble's text that lines up
    ///     with the source's `textAnchor`, in the layer.
    ///   - bubbleRadii: The real bubble's corners.
    ///   - layerOrigin: The layer's origin in global space, which the
    ///     source is measured in.
    init(
        at time: TimeInterval,
        from source: MessageSendSource,
        to bubble: CGRect,
        bubbleText: CGPoint,
        bubbleRadii: RectangleCornerRadii,
        layerOrigin: CGPoint
    ) {
        let field = source.fieldFrame.offsetBy(dx: -layerOrigin.x, dy: -layerOrigin.y)
        let slide = MessageSendMotion.slide(at: time)
        let rise = MessageSendMotion.rise(at: time)

        // Horizontally the fill narrows from the field's edges to the
        // bubble's; vertically it lifts from the field's, bottom first.
        let minX = Self.mix(field.minX, bubble.minX, slide)
        let maxX = Self.mix(field.maxX, bubble.maxX, slide)
        let minY = Self.mix(field.minY, bubble.minY, rise)
        let maxY = Self.mix(field.maxY, bubble.maxY, rise)
        fill = CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))

        let limit = min(fill.width, fill.height) / 2
        func corner(_ landed: CGFloat) -> CGFloat {
            min(Self.mix(source.fieldCornerRadius, landed, slide), limit)
        }
        cornerRadii = RectangleCornerRadii(
            topLeading: corner(bubbleRadii.topLeading),
            bottomLeading: corner(bubbleRadii.bottomLeading),
            bottomTrailing: corner(bubbleRadii.bottomTrailing),
            topTrailing: corner(bubbleRadii.topTrailing)
        )

        // The bubble as a whole, aligned to the field's leading and bottom
        // edges at first, plus the text's own way from the composer's text
        // to its place in the bubble.
        let start = CGSize(width: field.minX - bubble.minX, height: field.maxY - bubble.maxY)
        let carried = CGSize(width: start.width * (1 - slide), height: start.height * (1 - rise))
        let composerText = CGPoint(x: source.textAnchor.x - layerOrigin.x, y: source.textAnchor.y - layerOrigin.y)
        let own = CGSize(
            width: composerText.x - bubbleText.x - start.width,
            height: composerText.y - bubbleText.y - start.height
        )
        textOffset = CGSize(width: carried.width + own.width * (1 - rise), height: carried.height + own.height * (1 - rise))
        hasReflowed = MessageSendMotion.hasReflowed(at: time)
    }

    private static func mix(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }
}
