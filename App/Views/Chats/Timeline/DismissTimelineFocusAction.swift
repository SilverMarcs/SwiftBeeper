import SwiftUI

/// Returns the timeline from a shown quote or a reply's target, as a tap on
/// the space around the focused messages does. Nil while nothing focused can
/// be dismissed that way, as during an edit.
///
/// Rows read it to put the same backdrop behind themselves: a row's swipe
/// actions take taps across its whole width, so the timeline's own backdrop
/// never sees them.
struct DismissTimelineFocusAction: Equatable {
    /// What the action dismisses; equal IDs dismiss the same focus, so rows
    /// don't re-render each time the timeline rebuilds the closure.
    let id: String
    /// Spoken for the backdrop.
    let label: LocalizedStringKey
    let action: () -> Void

    func callAsFunction() {
        action()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

extension EnvironmentValues {
    @Entry var dismissTimelineFocus: DismissTimelineFocusAction?
}
