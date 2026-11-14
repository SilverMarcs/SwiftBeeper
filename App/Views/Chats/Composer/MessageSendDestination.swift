import SwiftUI

/// A bubble in flight, as it reports itself to the layer drawing its flight:
/// where it sits and how its text is laid out, both live, so the flight
/// lands wherever the timeline has moved it.
struct MessageSendDestination: Identifiable, Equatable {
    let id: UUID
    let bounds: Anchor<CGRect>
    let textLayouts: [Text.LayoutKey.AnchoredLayout]
    let joins: MessageBubbleJoins
}
