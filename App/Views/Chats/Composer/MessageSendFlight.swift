import SwiftUI

/// One bubble's flight. A shared clock survives the optimistic row being
/// replaced by its echo.
@MainActor
@Observable
final class MessageSendFlight: Identifiable {
    let id: UUID
    /// The composer as the draft left it.
    let source: MessageSendSource
    /// The sent text's length in UTF-16 units.
    let textLength: Int
    var startedAt: ContinuousClock.Instant?
    var confirmedMessageIDs: Set<String> = []

    /// The reflow worked out for the bubble's last layout.
    @ObservationIgnored private var cachedReflow: (layouts: [Text.Layout], anchor: CGPoint, reflow: MessageSendReflow?)?

    init(message: OutgoingMessage, source: MessageSendSource) {
        id = message.id
        self.source = source
        textLength = message.text.utf16.count
    }

    /// How the text moves from the composer's lines to the bubble's, worked
    /// out once per layout of the bubble's text.
    func reflow(for layouts: [Text.Layout], anchor: CGPoint) -> MessageSendReflow? {
        if let cachedReflow, cachedReflow.layouts == layouts, cachedReflow.anchor == anchor {
            return cachedReflow.reflow
        }
        let reflow = MessageSendReflow(layouts: layouts, textLength: textLength, source: source, anchor: anchor)
        cachedReflow = (layouts, anchor, reflow)
        return reflow
    }
}
