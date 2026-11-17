import SwiftUI

/// Back and Forward between recently opened chats, like a browser.
struct ChatHistoryNavigationButtons: View {
    @Environment(ChatStore.self) private var chatStore

    var body: some View {
        let history = chatStore.chatHistory
        ControlGroup {
            Button("Back", systemImage: "chevron.backward", action: chatStore.goBackInChatHistory)
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!history.canGoBack)
                .help("Go back to the previous chat")

            Button("Forward", systemImage: "chevron.forward", action: chatStore.goForwardInChatHistory)
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!history.canGoForward)
                .help("Go forward to the next chat")
        } label: {
            Label("Chat History", systemImage: "chevron.left.chevron.right")
        }
    }
}
