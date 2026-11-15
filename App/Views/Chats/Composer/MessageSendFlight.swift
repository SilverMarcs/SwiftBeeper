import SwiftUI

/// One bubble's flight. A shared clock survives the optimistic row being
/// replaced by its echo.
@MainActor
@Observable
final class MessageSendFlight: Identifiable {
    let id: UUID
    /// The composer as the draft left it.
    let source: MessageSendSource
    var startedAt: ContinuousClock.Instant?
    var confirmedMessageIDs: Set<String> = []

    /// The bubble's text, drawn once for the layout it was drawn for.
    @ObservationIgnored private var cachedText: (key: BubbleTextKey, picture: MessageSendPicture?)?

    private struct BubbleTextKey: Equatable {
        let layouts: [Text.Layout]
        let origins: [CGPoint]
        let size: CGSize
        let scale: CGFloat
    }

    init(message: OutgoingMessage, source: MessageSendSource) {
        id = message.id
        self.source = source
    }

    /// The bubble's own lines as its row lays them out, drawn once into a
    /// picture of the bubble's size, so the flight only moves them.
    /// - Parameters:
    ///   - origins: Each text's origin, from the bubble's top-left corner.
    ///   - size: The bubble's size.
    func bubbleText(layouts: [Text.Layout], origins: [CGPoint], size: CGSize, scale: CGFloat) -> MessageSendPicture? {
        let key = BubbleTextKey(layouts: layouts, origins: origins, size: size, scale: scale)
        if let cachedText, cachedText.key == key { return cachedText.picture }
        let renderer = ImageRenderer(content: Canvas { context, _ in
            for (layout, origin) in zip(layouts, origins) {
                var text = context
                text.translateBy(x: origin.x, y: origin.y)
                for line in layout {
                    text.draw(line)
                }
            }
        }
        .frame(width: size.width, height: size.height))
        renderer.scale = scale
        let picture = renderer.cgImage.map { MessageSendPicture(image: $0, frame: CGRect(origin: .zero, size: size)) }
        cachedText = (key, picture)
        return picture
    }
}
