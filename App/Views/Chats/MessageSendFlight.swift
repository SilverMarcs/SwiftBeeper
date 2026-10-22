import SwiftUI

/// A shared clock survives the optimistic row being replaced by its echo.
@MainActor
@Observable
final class MessageSendFlight: Identifiable {
    let id: UUID
    let chatID: String
    let sourceFrame: CGRect
    var startedAt: ContinuousClock.Instant?
    var confirmedMessageIDs: Set<String> = []

    init(message: OutgoingMessage, sourceFrame: CGRect) {
        id = message.id
        chatID = message.chatID
        self.sourceFrame = sourceFrame
    }

    nonisolated static let duration: TimeInterval = 0.55
    nonisolated private static let spring = Spring(response: duration * 0.25 / 0.38, dampingRatio: 0.8)

    nonisolated static func progress(since start: ContinuousClock.Instant?, at now: ContinuousClock.Instant) -> CGFloat {
        guard let start else { return 0 }
        let elapsed = start.duration(to: now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        guard seconds < duration else { return 1 }
        return spring.value(target: CGFloat(1), time: max(0, seconds))
    }
}
