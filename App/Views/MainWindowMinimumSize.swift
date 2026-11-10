#if os(macOS)
import SwiftUI

/// The main window's minimum size, with room for an open thread inspector at
/// its widest taken out of it.
///
/// SwiftUI applies this minimum to the split view beside the inspector, not
/// to the window as a whole. At the full 900pt, opening the inspector in a
/// window narrower than 900pt plus the inspector laid the split view out
/// wider than the window while the inspector animated in, pushing the sidebar
/// off the leading edge, then snapped it back. Taking the inspector's widest
/// width out leaves it room at any width in any window the minimum allows.
private struct MainWindowMinimumSize: ViewModifier {
    @Environment(ChatStore.self) private var chatStore

    func body(content: Content) -> some View {
        let inspectorRoom = chatStore.isThreadPresented ? MainWindowLayout.threadInspectorMaximumWidth : 0
        content
            .frame(
                minWidth: MainWindowLayout.minimumWidth - inspectorRoom,
                minHeight: MainWindowLayout.minimumHeight
            )
    }
}

extension View {
    /// Sets the main window's minimum size around the thread inspector.
    func mainWindowMinimumSize() -> some View {
        modifier(MainWindowMinimumSize())
    }
}
#endif
