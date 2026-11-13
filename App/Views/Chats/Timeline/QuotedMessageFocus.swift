import Foundation

/// A reply whose quote was tapped. The reply stays where it is in the
/// timeline, focused as a message being replied to is, with the messages it
/// quotes shown above it.
struct QuotedMessageFocus: Equatable {
    /// Each tap shows its chain afresh, from wherever its messages are then.
    let id = UUID()
    /// The reply's timeline row.
    let rowID: Message.ID
    /// The message the reply quotes.
    let quoted: Message
    /// For each quoted message whose own row was on screen at the tap, where
    /// that row ended, in the timeline content's space, keyed by row ID. Its
    /// bubble moves from there into the chain and back.
    var origins: [Message.ID: CGFloat] = [:]
    /// False while the chain returns to the timeline, before it's removed.
    /// The timeline no longer focuses on the reply meanwhile.
    var isPresented = true
}
