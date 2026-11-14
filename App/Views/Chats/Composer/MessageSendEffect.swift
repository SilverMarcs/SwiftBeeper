import SwiftUI

/// Hands a just-sent bubble to `MessageSendFlightLayer`, which draws it
/// above the composer, flying from the field to here. The bubble keeps its
/// place in the timeline, hidden, and reports where it is and how its text
/// is laid out on every pass, so the flight always lands on it exactly.
struct MessageSendEffect: ViewModifier {
    @Environment(InputManager.self) private var input
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.messageBubbleJoins) private var joins

    /// Finds this bubble's flight, if it was just sent.
    let flight: (MessageSendAnimator) -> MessageSendFlight?

    func body(content: Content) -> some View {
        let animator = input.sendAnimator
        if !reduceMotion, let flight = flight(animator) {
            let id = flight.id
            let joins = joins
            content
                .opacity(0)
                .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                    Color.clear.anchorPreference(key: MessageSendDestinationKey.self, value: .bounds) { bounds in
                        [MessageSendDestination(id: id, bounds: bounds, textLayouts: layouts, joins: joins)]
                    }
                }
                .onAppear { animator.start(id) }
        } else {
            content
        }
    }
}

extension View {
    /// Flies a just-sent bubble in from the composer. Apply it to the bubble
    /// itself, inside the `messageBubbleJoins` that shape it.
    func sendEffect(forOutgoing id: OutgoingMessage.ID) -> some View {
        modifier(MessageSendEffect { $0.flight(forOutgoing: id) })
    }

    /// Continues the flight on the server echo that replaced the outgoing row.
    /// Pass nil for incoming messages so they never observe flights.
    func sendEffect(forConfirmed id: Message.ID?) -> some View {
        modifier(MessageSendEffect { animator in id.flatMap { animator.flight(forConfirmed: $0) } })
    }
}
