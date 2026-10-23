#if os(iOS)
import SwiftUI

/// Animate the actual bubble relative to its current layout, never a copied
/// destination rectangle. Only render transforms change on animation frames.
struct MessageSendEffect: ViewModifier {
    let animator: MessageSendAnimator
    let flight: MessageSendFlight?

    func body(content: Content) -> some View {
        if let flight {
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
#endif
