import Foundation

/// Whether a timeline row's message is shown above a reply whose quote was
/// tapped, leaving the row only its space.
enum QuotedChainRowState: Equatable {
    case inTimeline
    /// `moves`: its copy left from this row and comes back to it, so the row
    /// hides and returns at once, under the copy, rather than fading.
    case shownAbove(moves: Bool)

    var isShownAbove: Bool { self != .inTimeline }
    var moves: Bool { self == .shownAbove(moves: true) }
}
