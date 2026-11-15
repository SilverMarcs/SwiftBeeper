import SwiftUI

/// The searchable chat list with its filter and Settings controls.
struct ChatSidebarView: View {
    @Environment(ChatStore.self) private var chatStore

    @State private var showingSettings = false
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchPresented = false

    var body: some View {
        @Bindable var chatStore = chatStore

        ChatListView()
            .searchable(
                text: $chatStore.searchQuery,
                isPresented: $isSearchPresented,
                placement: isIPhone ? .automatic : .sidebar
            )
            .searchFocused($isSearchFocused)
            // Search runs as you type; the Search key only puts the keyboard
            // away to read the results.
            .onSubmit(of: .search) { isSearchFocused = false }
            #if os(iOS)
            // Clear search focus when opening a result so returning to the
            // sidebar doesn't restore its keyboard. Message results can also
            // reopen the already-selected chat without changing its ID.
            .onChange(of: chatStore.selectedChatID) { isSearchFocused = false }
            .onChange(of: chatStore.chatNavigationID) { isSearchFocused = false }
            #endif
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .task(id: [chatStore.searchQuery, chatStore.selectedFilter.id, chatStore.session.uuidString]) {
                await chatStore.searchChats()
            }
            // Searching starts once the field is focused, before any text;
            // kept results, as after opening one, still read as a search.
            .navigationTitle(isSearchFocused || isSearchPresented || chatStore.isSearchActive ? "Search" : "Chats")
            .toolbarTitleDisplayMode(isIPad ? .inline : .inlineLarge)
            .toolbar(removing: isIPhone ? .sidebarToggle : nil)
            .toolbar {
                #if os(macOS)
                // Settings lives in the app's Settings scene.
                ToolbarSpacer()
                ToolbarItem(placement: .primaryAction) {
                    ChatFilterMenu()
                }
                #else
                if isIPhone {
                    if chatStore.isCatchingUp {
                        ToolbarItem(placement: .primaryAction) {
                            ChatSyncProgressView()
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
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
                    if chatStore.isCatchingUp {
                        ToolbarItem(placement: .primaryAction) {
                            ChatSyncProgressView()
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
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
