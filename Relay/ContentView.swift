import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(RealtimeCoordinator.self) private var coordinator

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
                }
            }
        }
        .task(id: sessionStore.accessToken.isEmpty) {
            await coordinator.updateAccessToken(sessionStore.accessToken)
        }
    }
}

#Preview {
    let chatStore = ChatStore()
    let messageStore = MessageStore()
    let realtimeService = RealtimeService()
    let notificationService = NotificationService()
    ContentView()
        .environment(SessionStore())
        .environment(chatStore)
        .environment(messageStore)
        .environment(RealtimeCoordinator(
            chatStore: chatStore,
            messageStore: messageStore,
            realtimeService: realtimeService,
            notificationService: notificationService
        ))
}
