import SwiftUI

/// The neighbours a bubble joins in its sender's run of bubbles. Joined
/// bubbles read as one block, as in Messages: the corners where two meet, on
/// the sender's side, round less than the rest. Rows work it out when they're
/// built, for their outer edges; each row hands its bubbles their share.
struct MessageBubbleJoins: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    /// The bubble carries on from one directly above it.
    static let above = MessageBubbleJoins(rawValue: 1 << 0)
    /// The bubble carries on into one directly below it.
    static let below = MessageBubbleJoins(rawValue: 1 << 1)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(above: Bool, below: Bool) {
        self = []
        if above { insert(.above) }
        if below { insert(.below) }
    }

    /// The joins of the bubble at `index` among `count` stacked in a row whose
    /// outer edges join as `self`: bubbles within the row always join.
    func bubble(at index: Int, of count: Int) -> MessageBubbleJoins {
        MessageBubbleJoins(above: index > 0 || contains(.above), below: index < count - 1 || contains(.below))
    }
}

extension EnvironmentValues {
    /// Set by a message row around its bubbles, for their outer edges, and by
    /// the row's content for each bubble. Nothing joins outside a run.
    @Entry var messageBubbleJoins: MessageBubbleJoins = []
}
