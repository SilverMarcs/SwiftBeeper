import SwiftUI

/// The space under a composer: a fixed margin on macOS; on iOS a small gap
/// above the keyboard whenever it is up, and none against the home indicator.
private struct ComposerBottomPadding: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.padding(.bottom, 12)
        #else
        content.padding(.bottom, KeyboardMonitor.shared.isVisible ? 8 : 0)
        #endif
    }
}

extension View {
    func composerBottomPadding() -> some View {
        modifier(ComposerBottomPadding())
    }
}
