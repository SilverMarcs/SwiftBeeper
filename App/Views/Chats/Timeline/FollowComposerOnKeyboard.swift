#if os(iOS)
import SwiftUI

/// Moves the timeline with the composer as the keyboard shows and hides. See
/// `TimelineKeyboardFollower`.
///
/// Apply it to the scroll view's content, so the introspector sits inside
/// the `UIScrollView` it looks for.
struct FollowComposerOnKeyboard: ViewModifier {
    @Environment(ChatStore.self) private var chatStore
    @State private var follower = TimelineKeyboardFollower()

    func body(content: Content) -> some View {
        content
            .background {
                EnclosingScrollViewIntrospector { scrollView in
                    // Reply and edit scroll to their message, not the newest.
                    follower.attach(to: scrollView) { [chatStore] in
                        chatStore.activeComposerMessage == nil
                    }
                } onDetach: { scrollView in
                    follower.detach(from: scrollView)
                }
                .accessibilityHidden(true)
            }
    }
}

extension View {
    /// Keeps the timeline moving with the composer as the keyboard shows and
    /// hides.
    func followsComposerOnKeyboard() -> some View {
        modifier(FollowComposerOnKeyboard())
    }
}
#endif
