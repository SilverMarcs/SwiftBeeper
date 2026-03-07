import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore

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
    }
}

#Preview {
    let chatStore = ChatStore()
    ContentView()
        .environment(SessionStore())
        .environment(chatStore)
        .environment(chatStore.messageStore)
}
