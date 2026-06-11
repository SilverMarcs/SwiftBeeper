import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore

    var body: some View {
        Group {
            if sessionStore.accessToken.isEmpty {
                OnboardingView()
            } else {
                NavigationSplitView {
                    ChatSidebarView()
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                } detail: {
                    ChatDetailView()
                        #if os(iOS)
                        .id(chatStore.selectedChatID)
                        #endif
                }
            }
        }
        .task(id: sessionStore.accessToken.isEmpty) {
            await chatStore.updateAccessToken(sessionStore.accessToken)
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionStore())
        .environment(ChatStore())
}
