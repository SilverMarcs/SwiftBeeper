import SwiftUI

extension View {
    /// Lets an info screen's header run up under the navigation bar on iOS: the
    /// content ignores the top safe area, and the bar shows neither its title nor
    /// a background, leaving only its buttons. The title is kept for the system,
    /// such as back-button menus and accessibility.
    func infoScreenChrome(title: LocalizedStringKey) -> some View {
        #if os(iOS)
        self
            // With the safe area gone, this alone keeps the avatar off the sheet's top edge,
            // roughly level with the bar's buttons.
            .contentMargins(.top, 30, for: .scrollContent)
            .ignoresSafeArea(.container, edges: .top)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .scrollEdgeEffectHidden(true, for: .top)
        #else
        self
            // The header carries its own spacing; the form's default top margin pushes it too far down.
            .contentMargins(.top, 5, for: .scrollContent)
        #endif
    }
}
