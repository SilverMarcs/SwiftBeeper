import SwiftUI

/// Hides the navigation bar while the composer is focused on a specific message (iOS only).
struct NavigationBarFocusVisibilityModifier: ViewModifier {
    let isFocusedOnComposerMessage: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbarVisibility(isFocusedOnComposerMessage ? .hidden : .visible, for: .navigationBar)
        #else
        content
        #endif
    }
}
