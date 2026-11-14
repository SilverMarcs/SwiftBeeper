import SwiftUI

/// Draws each just-sent bubble on its way from the composer, above both the
/// timeline and the composer, so it can grow out of the field itself rather
/// than from under the composer's glass.
struct MessageSendFlightLayer: View {
    /// The bubbles in flight, as they report themselves from the timeline.
    let destinations: [MessageSendDestination]
    @Environment(InputManager.self) private var input

    var body: some View {
        if !destinations.isEmpty {
            GeometryReader { proxy in
                let layerOrigin = proxy.frame(in: .global).origin
                ForEach(Self.latest(of: destinations)) { destination in
                    if let flight = input.sendAnimator.flight(forOutgoing: destination.id) {
                        MessageSendFlightView(
                            flight: flight,
                            bubble: proxy[destination.bounds],
                            textOrigins: destination.textLayouts.map { proxy[$0.origin] },
                            layouts: destination.textLayouts.map(\.layout),
                            joins: destination.joins,
                            layerOrigin: layerOrigin
                        )
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// One destination per flight. While the echo replaces the optimistic
    /// row both can report for a pass; the later one, the echo, wins.
    private static func latest(of destinations: [MessageSendDestination]) -> [MessageSendDestination] {
        var seen = Set<UUID>()
        return destinations.reversed().filter { seen.insert($0.id).inserted }.reversed()
    }
}
