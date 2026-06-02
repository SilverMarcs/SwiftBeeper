import SwiftUI

struct ChatSidebarView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore

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
                    .searchable(text: $chatStore.searchQuery, placement: .sidebar, prompt: "Search chats")
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
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarSpacer()

            ToolbarItem(placement: .primaryAction) {
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
        }
        .onChange(of: chatStore.selectedInboxFilter) {
            Task {
                await chatStore.loadChats()
            }
        }
    }

    private var chatList: some View {
        List(selection: Bindable(chatStore).selectedChatID) {
            ForEach(chatStore.displayedChats) { chat in
                ChatRowView(chat: chat)
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
        .listStyle(.sidebar)
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
