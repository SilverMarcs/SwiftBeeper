import SwiftUI

/// A flying bubble's fill: the composer's field turned into a bubble, taking
/// the real bubble's shape as it lands.
struct MessageSendFlightBubble: View {
    /// Where the fill is now, in the layer.
    let frame: CGRect
    let cornerRadii: RectangleCornerRadii

    var body: some View {
        Color.clear
            .bubbleBackground(isOutgoing: true)
            .clipShape(UnevenRoundedRectangle(cornerRadii: cornerRadii))
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }
}
