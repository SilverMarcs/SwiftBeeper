import SwiftUI

struct ChatSidebarView: View {
    @Environment(ChatStore.self) private var chatStore

    @State private var showingSettings = false

    var body: some View {
        @Bindable var chatStore = chatStore

        chatList
            .searchable(text: $chatStore.searchQuery, placement: isIPhone ? .automatic : .sidebar, prompt: "Search chats")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onSubmit(of: .search) { chatStore.submitSearch() }
        .navigationTitle("Chats")
        .toolbarTitleDisplayMode(isIPad ? .inline : .inlineLarge)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            #if !os(macOS)
            if isIPhone {
                // iPhone: gear opens Settings where the filter used to live;
                // the filter moves to the bottom bar, styled like ChatTimelineView.
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
        // Compute once for the rows and animation key.
        let displayedChats = chatStore.displayedChats
        return List(selection: Bindable(chatStore).selectedChatID) {
            ForEach(displayedChats) { chat in
                ChatRowView(chat: chat)
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(.visible, edges: .bottom)
                    .if(isMacOrPad) {
                        $0.listRowSeparatorTint(.primary.opacity(0.1), edges: .bottom)
                    }
                    .tag(chat.id)
            }

            if chatStore.hasMoreChats, chatStore.searchQuery.isBlank {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .task {
                        await chatStore.loadMoreChats()
                    }
            }
        }
        .if(isIPhone) { $0.listStyle(.plain) }
        // .if(isMacOrPad) { $0.listStyle(.sidebar) }
        // Animate only when the row order/membership changes (keyed on the id
        // sequence), not on in-place row edits like a chat's last-message text.
        .animation(.default, value: displayedChats.map(\.id))
        .overlay {
            ChatListOverlay(isEmpty: displayedChats.isEmpty)
        }
    }
}
