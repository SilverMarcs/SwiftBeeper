import SwiftUI

/// A flying bubble's text inside its fill: the draft's lines as the composer
/// drew them, then the bubble's own. Both are pictures drawn once, which
/// only move from frame to frame.
struct MessageSendFlightText: View {
    let frame: MessageSendFrame
    /// The bubble's lines, and where the bubble is, in the layer.
    let bubbleText: MessageSendPicture?
    let bubble: CGRect
    /// The composer's lines, where the composer drew them, in the layer.
    let composerText: MessageSendPicture?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let composerText, !frame.hasReflowed {
                Image(decorative: composerText.image, scale: composerText.scale)
                    .offset(
                        x: composerText.frame.minX + frame.composerTextOffset.width,
                        y: composerText.frame.minY + frame.composerTextOffset.height
                    )
            } else if let bubbleText {
                Image(decorative: bubbleText.image, scale: bubbleText.scale)
                    .offset(x: bubble.minX + frame.textOffset.width, y: bubble.minY + frame.textOffset.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The fill is a window: lines the field didn't show come into view
        // as it grows into the bubble.
        .mask(alignment: .topLeading) {
            UnevenRoundedRectangle(cornerRadii: frame.cornerRadii)
                .frame(width: frame.fill.width, height: frame.fill.height)
                .offset(x: frame.fill.minX, y: frame.fill.minY)
        }
    }
}
