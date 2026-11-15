import SwiftUI

extension ScrollGeometry {
    /// How far beyond the end counts, past rounding.
    private static let pastEndTolerance: CGFloat = 2

    /// Whether content taller than the view rests beyond where it can scroll
    /// to at its end, its newest rows drawn above the bottom with empty space
    /// below them.
    ///
    /// `containerSize` leaves out the content insets, so the end is where
    /// the content's bottom meets the view's above the bottom inset.
    var isPastEnd: Bool {
        guard contentSize.height > containerSize.height else { return false }
        let end = contentSize.height - containerSize.height - contentInsets.top
        return contentOffset.y > end + Self.pastEndTolerance
    }
}
