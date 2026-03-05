import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(MessageStore.self) private var messageStore

    var body: some View {
        NavigationSplitView {
            ChatSidebarView()
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            ChatDetailView()
        }
        .task(id: sessionStore.accessToken) {
            await chatStore.updateAccessToken(sessionStore.accessToken)
        }
        .onChange(of: chatStore.selectedChatID) { _, newChatID in
            chatStore.realtimeService.selectedChatID = newChatID
            guard let newChatID else { return }

            Task {
                await messageStore.loadMessagesIfNeeded(for: newChatID)
            }
        }
    }
}

#Preview {
    let chatStore = ChatStore()
    ContentView()
        .environment(SessionStore())
        .environment(chatStore)
        .environment(chatStore.messageStore)
}
