import SwiftUI

/// Marks the oldest unread mention reached once its row is on screen, so the
/// Next Mention shortcut doesn't offer one the reader can already see. Rows
/// report coming on screen as they move; this covers the mention list
/// arriving, or moving on, while they stand still. A modifier of its own so
/// only it, not the whole timeline, re-renders as the list changes.
struct TimelineSeenMentions: ViewModifier {
    let mentions: MentionNavigation
    let frames: TimelineRowFrames
    let topInset: CGFloat

    func body(content: Content) -> some View {
        content
            .onChange(of: mentions.mentions.first?.id, initial: true) { _, id in
                guard let id, frames.isVisible(id, below: topInset) else { return }
                mentions.didSee(id)
            }
    }
}
