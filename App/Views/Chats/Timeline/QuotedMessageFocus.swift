import Foundation

/// A reply whose quote was tapped. The reply stays where it is in the
/// timeline, focused as a message being replied to is, with the messages it
/// quotes shown above it.
struct QuotedMessageFocus: Equatable {
    /// The reply's timeline row.
    let rowID: Message.ID
    /// The message the reply quotes.
    let quoted: Message
}
