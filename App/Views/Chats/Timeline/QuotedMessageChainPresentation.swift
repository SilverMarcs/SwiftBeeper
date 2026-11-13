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
    let isPresented: Bool
}
