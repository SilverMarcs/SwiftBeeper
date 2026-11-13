import SwiftUI

/// The chat's avatar, centred in the navigation bar as in Messages. It's
/// taller than the bar, so it hangs below it, down to the name capsule under
/// the bar. Opens chat info.
struct ChatHeaderAvatarButton: View {
    let chat: Chat
    let action: () -> Void

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var body: some View {
        Button(action: action) {
            ChatAvatarView(chat: chat, dimension: metrics.dimension)
        }
        .buttonStyle(.plain)
        // Moves the avatar down without growing the bar, so its top lines up
        // with the bar's buttons.
        .offset(y: metrics.overhang)
        // The name capsule below is the same button, with a readable label.
        .accessibilityHidden(true)
    }

    private var metrics: (dimension: CGFloat, overhang: CGFloat) {
        #if os(macOS)
        (44, 10)
        #else
        // A landscape iPhone's bar is too short to hang a large avatar from.
        verticalSizeClass == .compact ? (30, 0) : (60, 8)
        #endif
    }
}
