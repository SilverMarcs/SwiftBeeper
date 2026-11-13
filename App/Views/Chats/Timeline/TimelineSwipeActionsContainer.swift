import SwiftUI

/// Makes the timeline's scroll view coordinate its rows' swipe actions as a
/// `List` does: one row open at a time, closed by scrolling or by tapping
/// another row. Needs iOS and macOS 27; earlier systems show no swipe actions.
struct TimelineSwipeActionsContainer: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27, macOS 27, *) {
            content.swipeActionsContainer()
        } else {
            content
        }
    }
}

extension View {
    /// Coordinates the swipe actions of the rows in this scroll view.
    func timelineSwipeActionsContainer() -> some View {
        modifier(TimelineSwipeActionsContainer())
    }
}
