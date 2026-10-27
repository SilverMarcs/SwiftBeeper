import SwiftUI

/// Animate the actual bubble relative to its current layout, never a copied
/// destination rectangle. Only render transforms change on animation frames.
struct MessageSendEffect: ViewModifier {
    @Environment(InputManager.self) private var input
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Finds this bubble's flight, if it was just sent.
    let flight: (MessageSendAnimator) -> MessageSendFlight?

    func body(content: Content) -> some View {
        let animator = input.sendAnimator
        if !reduceMotion, let flight = flight(animator) {
            let source = flight.sourceFrame
            let startedAt = flight.startedAt
            TimelineView(.animation) { _ in
                let progress = MessageSendFlight.progress(since: startedAt, at: .now)
                content
                    .visualEffect { bubble, geometry in
                        let destination = geometry.frame(in: .global)
                        let remaining = 1 - progress
                        return bubble
                            .scaleEffect(0.9 + 0.1 * progress)
                            .offset(
                                x: (source.midX - destination.midX) * remaining,
                                y: (source.midY - destination.midY) * remaining
                            )
                    }
            }
            .onAppear { animator.start(flight.id) }
        } else {
            content
        }
    }
}

extension View {
    /// Flies a just-sent bubble in from the composer.
    func sendEffect(forOutgoing id: OutgoingMessage.ID) -> some View {
        modifier(MessageSendEffect { $0.flight(forOutgoing: id) })
    }

    /// Continues the flight on the server echo that replaced the outgoing row.
    /// Pass nil for incoming messages so they never observe flights.
    func sendEffect(forConfirmed id: Message.ID?) -> some View {
        modifier(MessageSendEffect { animator in id.flatMap { animator.flight(forConfirmed: $0) } })
    }
}
