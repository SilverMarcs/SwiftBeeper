import SwiftUI

struct HiddenToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem {
                    Color.clear
                }
                .sharedBackgroundVisibility(.hidden)
            }
        #else
        // The window toolbar this hides is a macOS concept; nothing to do on iOS.
        content
        #endif
    }
}
