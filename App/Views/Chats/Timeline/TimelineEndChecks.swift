/// The moves that follow a jump to the timeline's end, while SwiftUI is still
/// landing it. Each is checked against the last row, which lays out the rows
/// a lazy stack can otherwise leave undrawn; see `ChatTimelineView`.
///
/// Checks run out after a few moves or a moment, whichever comes first, so a
/// reader's scroll that follows is never taken for the jump.
///
/// It's a plain class rather than view state, so scrolling never re-renders
/// the timeline's rows.
@MainActor
final class TimelineEndChecks {
    /// SwiftUI can move the offset a few times before a jump settles.
    private static let moveCount = 3
    /// A jump's moves arrive within a few frames of it.
    private static let window: Duration = .milliseconds(500)

    private var remaining = 0
    private var deadline = ContinuousClock.now

    /// Starts checking the moves after a jump to the end.
    func arm() {
        remaining = Self.moveCount
        deadline = .now + Self.window
    }

    func cancel() {
        remaining = 0
    }

    /// Whether this move may still be the jump landing, using up a check.
    func take() -> Bool {
        guard remaining > 0, ContinuousClock.now < deadline else {
            remaining = 0
            return false
        }
        remaining -= 1
        return true
    }
}
