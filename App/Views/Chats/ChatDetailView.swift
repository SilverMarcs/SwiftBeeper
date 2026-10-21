import SwiftUI

/// Platform dispatcher for the chat detail pane. The macOS and iOS
/// implementations live in `ChatDetailMac` / `ChatDetailiOS`; they're
/// identical for now but are kept separate so each can diverge as the
/// platforms' chat UIs grow apart.
struct ChatDetailView: View {
    @Environment(ChatStore.self) private var chatStore
    @State private var isVisible = false

    var body: some View {
        let chatID = chatStore.selectedChatID
        Group {
            #if os(macOS)
            ChatDetailMac()
            #else
            ChatDetailiOS()
            #endif
        }
        .onAppear {
            isVisible = true
            chatStore.visibleChatID = chatID
        }
        .onDisappear {
            isVisible = false
            if chatStore.visibleChatID == chatID { chatStore.visibleChatID = nil }
        }
        .onChange(of: chatID) { _, newValue in
            if isVisible { chatStore.visibleChatID = newValue }
        }
    }
}
