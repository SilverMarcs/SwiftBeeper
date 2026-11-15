import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        Group {
            if !sessionStore.isSignedIn {
                OnboardingView()
            } else {
                NavigationSplitView(
                    columnVisibility: $columnVisibility,
                    preferredCompactColumn: $preferredCompactColumn
                ) {
                    ChatSidebarView()
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                } detail: {
                    // One detail for every chat, as on macOS: the timeline
                    // viewport and composer re-key themselves per chat.
                    ChatDetailView(chatID: chatStore.selectedChatID, toggleSidebar: toggleSidebar)
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

    private func toggleSidebar() {
        withAnimation {
            if horizontalSizeClass == .compact {
                preferredCompactColumn = .sidebar
            } else {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionStore())
        .environment(ChatStore())
}
