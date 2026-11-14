import Foundation

/// A copy of part of a row, shown elsewhere while a tapped quote's chain
/// shows, that moves from where the part sat.
struct QuotedMorphCopy: Equatable {
    /// One per tap; see `QuotedMessageFocus.id`.
    let id: UUID
    /// Where the part ended, in the timeline content's space; nil fades the
    /// copy in instead.
    let origin: CGFloat?
    let isPresented: Bool
}
