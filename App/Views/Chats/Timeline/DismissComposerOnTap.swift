#if os(iOS)
import SwiftUI

/// Closes the composer as soon as the reader taps the timeline, without
/// keeping the tap from rows and buttons beneath it.
///
/// Apply it to the scroll view's content, so the introspector sits inside
/// the `UIScrollView` it looks for.
struct DismissComposerOnTap: ViewModifier {
    @State private var recognizer = TimelineTapRecognizer()
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .environment(\.timelineTapRecognizer, recognizer)
            .background {
                EnclosingScrollViewIntrospector { scrollView in
                    recognizer.onTap = dismiss
                    recognizer.install(in: scrollView)
                } onDetach: { scrollView in
                    recognizer.remove(from: scrollView)
                }
                .accessibilityHidden(true)
            }
    }
}

extension View {
    /// Closes the composer when the timeline around this content is tapped.
    func dismissesComposerOnTap(_ dismiss: @escaping () -> Void) -> some View {
        modifier(DismissComposerOnTap(dismiss: dismiss))
    }
}

extension EnvironmentValues {
    /// Lets native row swipe actions exclude their touches from tap dismissal.
    @Entry var timelineTapRecognizer: TimelineTapRecognizer?
}
#endif
