import SwiftUI

/// The searchable chat list with its filter and Settings controls.
struct ChatSidebarView: View {
    @Environment(ChatStore.self) private var chatStore

    @State private var showingSettings = false

    var body: some View {
        @Bindable var chatStore = chatStore

        ChatListView()
            .searchable(text: $chatStore.searchQuery, placement: isIPhone ? .automatic : .sidebar, prompt: "Search chats")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .task(id: [chatStore.searchQuery, chatStore.selectedFilter.id, chatStore.session.uuidString]) {
                await chatStore.searchChats()
            }
            .navigationTitle("Chats")
            .toolbarTitleDisplayMode(isIPad ? .inline : .inlineLarge)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                #if os(macOS)
                // Settings lives in the app's Settings scene.
                ToolbarSpacer()
                ToolbarItem(placement: .primaryAction) {
                    ChatFilterMenu()
                }
                #else
                if isIPhone {
                    // Search and the filter share the bottom bar, like the
                    // chat's composer and attachment menu.
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gear") { showingSettings = true }
                    }
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        ChatFilterMenu()
                    }
                } else if isIPad {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Settings", systemImage: "gear") { showingSettings = true }
                    }
                    ToolbarSpacer()
                    ToolbarItem(placement: .primaryAction) {
                        ChatFilterMenu()
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .onChange(of: chatStore.selectedFilter) {
                Task {
                    await chatStore.loadChats()
                }
            }
    }
}
