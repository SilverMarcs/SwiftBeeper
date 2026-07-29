import SwiftUI

struct ContentView: View {
    @Environment(ServerConnection.self) private var serverConnection
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @State private var showsSettings = false

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
        .overlay(alignment: .topTrailing) {
            if sessionStore.accessToken.isEmpty {
                Button("Server Settings", systemImage: "gear") {
                    showsSettings = true
                }
                .labelStyle(.iconOnly)
                .padding()
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
                .environment(serverConnection)
                .environment(sessionStore)
                .environment(chatStore)
        }
    }
}

#Preview {
    ContentView()
        .environment(ServerConnection())
        .environment(SessionStore())
        .environment(ChatStore())
}
