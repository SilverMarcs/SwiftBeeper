import SwiftUI

/// Presents the open thread in an inspector on the whole split view, so it
/// takes a full-height trailing column on macOS and iPad. Compact widths show
/// the inspector as a sheet. The thread outlives its presentation, so the
/// inspector keeps its content while it hides.
private struct ThreadPresentation: ViewModifier {
    @Environment(ChatStore.self) private var chatStore

    func body(content: Content) -> some View {
        content
            .inspector(isPresented: Bindable(chatStore).isThreadPresented) {
                if let thread = chatStore.activeThread {
                    Group {
                        #if os(iOS)
                        // Its own stack gives the inspector a title bar, and the
                        // iPhone composer its search field and bottom bar.
                        NavigationStack {
                            threadView(thread)
                        }
                        #else
                        threadView(thread)
                        #endif
                    }
                    #if os(macOS)
                    // The window's minimum leaves room for the widest.
                    .inspectorColumnWidth(
                        min: MainWindowLayout.threadInspectorMinimumWidth,
                        ideal: MainWindowLayout.threadInspectorIdealWidth,
                        max: MainWindowLayout.threadInspectorMaximumWidth
                    )
                    #else
                    .inspectorColumnWidth(min: 300, ideal: 380, max: 560)
                    #endif
                }
            }
    }

    /// The thread's timeline and composer, the same as the chat's.
    private func threadView(_ thread: ThreadStore) -> some View {
        ChatTimelineView(source: thread)
            #if os(iOS)
            // macOS keeps the window title for the chat.
            .navigationTitle("Thread")
            .navigationSubtitle(thread.chat.displayTitle)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // A hidden inspector's content stays in the hierarchy, and
                // so would its toolbar.
                if chatStore.isThreadPresented {
                    #if os(macOS)
                    // The inspector's toolbar section starts at its leading edge.
                    ToolbarSpacer(.flexible)
                    #endif
                    ToolbarItem(placement: .primaryAction) {
                        Button("Close Thread", systemImage: "xmark") {
                            chatStore.closeThread()
                        }
                    }
                }
            }
    }
}

extension View {
    /// Shows the open thread beside the chat.
    func presentsThreads() -> some View {
        modifier(ThreadPresentation())
    }
}
