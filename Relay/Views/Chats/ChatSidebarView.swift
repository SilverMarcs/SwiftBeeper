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
                    .searchPresentationToolbarBehavior(.avoidHidingContent)
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
            #if !os(macOS)
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
            }
            #else
                // macOS: unchanged — Settings lives in the app's Settings scene.
                ToolbarSpacer()
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
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

    private var filterMenu: some View {
        Menu {
            Section("Inboxes") {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    Toggle(isOn: Binding(
                        get: { chatStore.selectedFilter == .inbox(filter) },
                        set: { if $0 { chatStore.selectedFilter = .inbox(filter) } }
                    )) {
                        Label(filter.label, systemImage: filter.systemImage)
                    }
                }
            }

            Divider()

            Section("Services") {
                ForEach(chatStore.availableServiceFilters, id: \.self) { filter in
                    Toggle(isOn: Binding(
                        get: { chatStore.selectedFilter == filter },
                        set: { if $0 { chatStore.selectedFilter = filter } }
                    )) {
                        Text(filter.label)
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        .menuOrder(.fixed)
        .menuIndicator(.hidden)
        .fixedSize()
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
                    .if(isIPhone) {
                        $0.listRowSeparator(.hidden, edges: .top)
                            .listRowSeparator(.visible, edges: .bottom)
                    }
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
        .if(isIPhone) { $0.listStyle(.plain) }
        // .if(isMacOrPad) { $0.listStyle(.sidebar) }
        // Animate only when the row order/membership changes (keyed on the id
        // sequence), not on in-place row edits like a chat's last-message text.
        .animation(.default, value: chatStore.displayedChats.map(\.id))
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
