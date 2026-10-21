import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        Group {
            if sessionStore.accessToken.isEmpty {
                OnboardingView()
            } else {
                NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
                    ChatSidebarView()
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                } detail: {
                    ChatDetailView()
                        #if os(iOS)
                        .id(chatStore.selectedChatID)
                        #endif
                }
                .onChange(of: chatStore.notificationSelectionID) {
                    preferredCompactColumn = .detail
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
