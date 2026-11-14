import Foundation

/// What the reply whose quote was tapped shows above itself: the quoted
/// messages, where those on screen came from, and whether the chain is
/// showing or on its way back to the timeline.
struct QuotedMessageChainPresentation: Equatable {
    /// One per tap; see `QuotedMessageFocus.id`.
    let id: UUID
    let entries: [TimelineEntry]
    /// Keyed by row ID; see `QuotedMessageFocus.origins`.
    let origins: [Message.ID: CGFloat]
    /// In a group, the reply's sender, whose name ends the chain, just above
    /// the reply's bubble, and where that name came from.
    let senderName: Message?
    let senderNameOrigin: CGFloat?
    /// Who sent the reply, for the space between its bubble and the last
    /// quoted message, wider where the sender changes.
    let replySenderID: String?
    /// How far the timeline's content reaches up under its header. Copies
    /// with no row on screen start at least that far above the timeline's
    /// top edge, so they cross the header quickly instead of easing in and
    /// out of sight beneath it.
    let headerHeight: CGFloat
    let isPresented: Bool
}
