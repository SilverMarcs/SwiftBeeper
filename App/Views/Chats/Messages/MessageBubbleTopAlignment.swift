import SwiftUI

extension VerticalAlignment {
    private struct MessageBubbleTop: AlignmentID {
        /// Views that don't set it, such as a quote's chain, meet the
        /// bubbles with their bottom edge.
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.bottom]
        }
    }

    /// The top of a message row's bubbles, below its sender's name and its
    /// quote, where a tapped quote's chain stands.
    static let messageBubbleTop = VerticalAlignment(MessageBubbleTop.self)
}
