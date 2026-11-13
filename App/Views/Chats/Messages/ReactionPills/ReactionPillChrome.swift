import SwiftUI

/// A reaction pill's capsule: its fill, ringed with the timeline's background
/// so it stands apart from the bubble it overlaps, as in Messages.
struct ReactionPillChrome: ViewModifier {
    /// Whether the pill is the user's own, filled with the accent color.
    let isOwn: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background { ReactionPillFill(isOwn: isOwn) }
            .clipShape(.capsule)
            .padding(ChatVisualStyle.reactionPillRingWidth)
            .background(.background, in: .capsule)
            .contentShape(.capsule)
    }
}

extension View {
    func reactionPillChrome(isOwn: Bool) -> some View {
        modifier(ReactionPillChrome(isOwn: isOwn))
    }
}
