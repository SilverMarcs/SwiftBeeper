import SwiftUI

/// Platform dispatcher for the chat detail pane. The macOS and iOS
/// implementations live in `ChatDetailMac` / `ChatDetailiOS`; they're
/// identical for now but are kept separate so each can diverge as the
/// platforms' chat UIs grow apart.
struct ChatDetailView: View {
    #if !os(macOS)
    @Environment(ChatStore.self) private var chatStore
    #endif

    var body: some View {
        #if os(macOS)
        ChatDetailMac()
        #else
        // iOS-only: NavigationSplitView aggressively reuses the detail column,
        // so `.task(id: selectedChat.id)` inside ChatDetailiOS doesn't reliably
        // re-fire on chat switch. Re-id'ing the concrete view forces a clean
        // rebuild (and a fresh `.task` / loadMessages) for every chat. macOS
        // doesn't need this — its detail re-fires the task on its own.
        ChatDetailiOS()
            .id(chatStore.selectedChatID)
        #endif
    }
}
