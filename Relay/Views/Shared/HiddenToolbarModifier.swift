import SwiftUI

struct HiddenToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem {
                    Color.clear
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
