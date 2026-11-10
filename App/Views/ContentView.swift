import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        Group {
            if !sessionStore.isSignedIn {
                OnboardingView()
            } else {
                NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
                    ChatSidebarView()
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                } detail: {
                    // One detail for every chat, as on macOS: the timeline
                    // viewport and composer re-key themselves per chat.
                    ChatDetailView(chatID: chatStore.selectedChatID)
                }
                .presentsThreads()
                .onChange(of: chatStore.chatNavigationID) {
                    preferredCompactColumn = .detail
                }
            }
        }
        .alert("Could Not Update Notifications", isPresented: Binding(
            get: { chatStore.muteError != nil },
            set: { if !$0 { chatStore.muteError = nil } }
        )) {
            Button("OK") { chatStore.muteError = nil }
        } message: {
            Text(chatStore.muteError ?? "")
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionStore())
        .environment(ChatStore())
}
