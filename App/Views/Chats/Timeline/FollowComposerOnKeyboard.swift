#if os(iOS)
import SwiftUI

/// Moves the timeline with the composer as the keyboard shows and hides. See
/// `TimelineKeyboardFollower`.
///
/// Apply it to the scroll view's content, so the introspector sits inside
/// the `UIScrollView` it looks for.
struct FollowComposerOnKeyboard: ViewModifier {
    let composer: Composer
    @State private var follower = TimelineKeyboardFollower()

    func body(content: Content) -> some View {
        content
            .background {
                EnclosingScrollViewIntrospector { scrollView in
                    // Reply and edit scroll to their message, not the newest.
                    follower.attach(to: scrollView) { [composer] in
                        composer.activeMessage == nil
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
    func followsComposerOnKeyboard(_ composer: Composer) -> some View {
        modifier(FollowComposerOnKeyboard(composer: composer))
    }
}
#endif
