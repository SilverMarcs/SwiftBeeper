import Foundation

/// What a timeline row does with one of its parts, its bubble, its sender's
/// name or avatar, or its quote, while a tapped quote's chain shows.
enum QuotedFocusHandoff: Equatable {
    /// The part stays in the row.
    case kept
    /// A copy moved out of the row, from where the part sat, and comes back
    /// to it; the part hides and returns at once, under the copy.
    case moved
    /// A copy shows elsewhere without moving, or the part has no use while
    /// the chain shows; the part fades out and back in.
    case faded
}
