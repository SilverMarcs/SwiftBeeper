import SwiftUI

/// One sent bubble in flight: the composer's field turns into the bubble,
/// narrowing to its side and rising into place with the text riding inside,
/// reflowing from the composer's lines into the bubble's.
/// Everything is measured against the real bubble's live position, so it
/// lands exactly on it.
struct MessageSendFlightView: View {
    let flight: MessageSendFlight
    /// The real bubble, in the layer.
    let bubble: CGRect
    /// The real bubble's texts' origins, in the layer.
    let textOrigins: [CGPoint]
    let layouts: [Text.Layout]
    let joins: MessageBubbleJoins
    let layerOrigin: CGPoint

    var body: some View {
        let startedAt = flight.startedAt
        let source = flight.source
        let bubbleShape = ChatVisualStyle.bubbleShape(isOutgoing: true, joins: joins)
        let bubbleText = textAnchor(linedUpWith: source)
        let reflow = textOrigins.first.flatMap { origin in
            flight.reflow(for: layouts, anchor: CGPoint(x: bubbleText.x - origin.x, y: bubbleText.y - origin.y))
        }
        TimelineView(.animation) { _ in
            let frame = MessageSendFrame(
                at: MessageSendMotion.elapsed(since: startedAt, at: .now),
                from: source,
                to: bubble,
                bubbleText: bubbleText,
                bubbleRadii: bubbleShape.cornerRadii,
                layerOrigin: layerOrigin
            )
            ZStack(alignment: .topLeading) {
                MessageSendFlightBubble(frame: frame.fill, cornerRadii: frame.cornerRadii)
                MessageSendFlightText(frame: frame, layouts: layouts, textOrigins: textOrigins, reflow: reflow)
            }
        }
    }

    /// The point of the bubble's text that lines up with the composer's: its
    /// first line's top leading corner, or its last line's bottom leading
    /// corner for a draft that was scrolled down.
    private func textAnchor(linedUpWith source: MessageSendSource) -> CGPoint {
        guard let first = textOrigins.first else {
            return CGPoint(
                x: bubble.minX + ChatVisualStyle.bubbleHorizontalPadding,
                y: source.anchorsLastLine
                    ? bubble.maxY - ChatVisualStyle.bubbleVerticalPadding
                    : bubble.minY + ChatVisualStyle.bubbleVerticalPadding
            )
        }
        guard source.anchorsLastLine, let origin = textOrigins.last, let line = layouts.last?.last else {
            return first
        }
        return CGPoint(x: first.x, y: origin.y + line.typographicBounds.rect.maxY)
    }
}
