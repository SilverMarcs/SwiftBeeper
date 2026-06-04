import SwiftUI

struct ChatSidebarView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore

    @State private var showingSettings = false

    var body: some View {
        @Bindable var chatStore = chatStore

        Group {
            if sessionStore.accessToken.isEmpty {
                TokenRequiredView(
                    title: "Missing Token",
                    systemImage: "key.fill",
                    description: "Open Settings and add your Beeper bearer token."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chatList
                    .searchable(text: $chatStore.searchQuery, placement: isIPhone ? .automatic : .sidebar, prompt: "Search chats")
                    .task(id: chatStore.searchQuery) {
                        if chatStore.searchQuery.isBlank {
                            chatStore.searchResults = nil
                            chatStore.isSearching = false
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(300))
                        await chatStore.searchChats()
                    }
                    .task(id: chatStore.chatsErrorIsAuth) {
                        if chatStore.chatsErrorIsAuth {
                            await chatStore.recoverAuthAndReload()
                        }
                    }
            }
        }
        .navigationTitle("Chats")
        .toolbarTitleDisplayMode(isIPad ? .inline : .inlineLarge)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            if isIPhone {
                // iPhone: gear opens Settings where the filter used to live;
                // the filter moves to the bottom bar, styled like ChatDetailiOS.
                ToolbarItem(placement: .primaryAction) {
                    settingsButton
                }
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    filterMenu
                }
            } else if isIPad {
                // iPad: Settings on the cancellation side, filter stays put.
                ToolbarItem(placement: .cancellationAction) {
                    settingsButton
                }
                ToolbarSpacer()
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
            } else {
                // macOS: unchanged — Settings lives in the app's Settings scene.
                ToolbarSpacer()
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .onChange(of: chatStore.selectedInboxFilter) {
            Task {
                await chatStore.loadChats()
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(InboxFilter.allCases, id: \.self) { filter in
                Button {
                    chatStore.selectedInboxFilter = filter
                } label: {
                    Label(filter.label, systemImage: filter.systemImage)
                }
            }
        } label: {
            Label(chatStore.selectedInboxFilter.label, systemImage: "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Label("Settings", systemImage: "gear")
        }
    }

    private var chatList: some View {
        List(selection: Bindable(chatStore).selectedChatID) {
            ForEach(chatStore.displayedChats) { chat in
                ChatRowView(chat: chat)
                     .listRowSeparator(.hidden, edges: .top)
                      .listRowSeparator(.visible, edges: .bottom)
                    .tag(chat.id)
                    .onAppear {
                        if chat.id == chatStore.displayedChats.last?.id,
                           chatStore.hasMoreChats,
                           !chatStore.isLoadingMoreChats {
                            Task {
                                await chatStore.loadMoreChats()
                            }
                        }
                    }
            }

            if chatStore.isLoadingMoreChats {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if chatStore.chats.isEmpty {
                if chatStore.isSearching
                    || chatStore.isLoadingChats
                    || chatStore.isRecoveringAuth
                    || chatStore.chatsErrorIsAuth {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let chatsError = chatStore.chatsError {
                    ContentUnavailableView(
                        "Could Not Load Chats",
                        systemImage: "exclamationmark.triangle",
                        description: Text(chatsError)
                    )
                }
            } else if chatStore.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
