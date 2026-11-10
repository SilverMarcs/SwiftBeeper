/// Whether the reader left the timeline at its newest message, as of the
/// last time they scrolled it. Unlike the live position, the keyboard
/// covering the end doesn't change it, so focusing the composer can tell a
/// reader at the end from one who scrolled back.
///
/// It's a plain class rather than view state, so scrolling never re-renders
/// the timeline's rows.
final class TimelineRestingPosition {
    var isAtEnd = true
}
