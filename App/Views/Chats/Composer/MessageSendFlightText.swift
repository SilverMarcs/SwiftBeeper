import SwiftUI

/// A flying bubble's text, drawn from the real bubble's layout inside its
/// fill. It starts exactly where the composer drew the draft; a message the
/// composer wrapped differently takes the bubble's lines on the way.
struct MessageSendFlightText: View {
    let frame: MessageSendFrame
    let layouts: [Text.Layout]
    /// The real bubble's texts' origins, in the layer.
    let textOrigins: [CGPoint]
    let reflow: MessageSendReflow?

    var body: some View {
        Canvas { context, _ in
            // The fill is a window: lines the field didn't show come into
            // view as it grows into the bubble.
            context.clip(to: UnevenRoundedRectangle(cornerRadii: frame.cornerRadii).path(in: frame.fill))
            context.translateBy(x: frame.textOffset.width, y: frame.textOffset.height)

            // Until it has reflowed, the text keeps the composer's lines.
            if let reflow, !frame.hasReflowed, let origin = textOrigins.first {
                context.translateBy(x: origin.x, y: origin.y)
                for glyph in reflow.glyphs {
                    guard let start = glyph.start else { continue }
                    var drawn = context
                    drawn.translateBy(x: start.width, y: start.height)
                    drawn.draw(glyph.slice)
                }
                return
            }
            for (layout, origin) in zip(layouts, textOrigins) {
                var text = context
                text.translateBy(x: origin.x, y: origin.y)
                for line in layout {
                    text.draw(line)
                }
            }
        }
    }
}
