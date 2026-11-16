import SwiftUI

extension EnvironmentValues {
    @Entry var incomingMessageIDs: Set<Message.ID> = []
}

/// A small arrival spring independent of the row's insertion transaction.
/// It also works when a message inherits an existing typing row's identity.
struct IncomingMessageEffect: ViewModifier {
    let messages: [Message]
    @Environment(\.incomingMessageIDs) private var incomingMessageIDs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = 0

    func body(content: Content) -> some View {
        let arrivalID = messages.last { incomingMessageIDs.contains($0.id) }?.id
        let reduceMotion = reduceMotion
        content
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { content, amount in
                content
                    .offset(y: reduceMotion ? 0 : 10 * amount)
                    .opacity(1 - min(1, max(0, amount)))
            } keyframes: { _ in
                MoveKeyframe(1)
                if reduceMotion {
                    LinearKeyframe(0, duration: 0.15)
                } else {
                    SpringKeyframe(0, duration: 0.5, spring: .init(duration: 0.32, bounce: 0.18))
                }
            }
            .onChange(of: arrivalID, initial: true) { _, id in
                guard id != nil else { return }
                trigger += 1
            }
    }
}
