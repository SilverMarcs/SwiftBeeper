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
            } else if let chatsError = chatStore.chatsError, chatStore.chats.isEmpty {
                ContentUnavailableView(
                    "Could Not Load Chats",
                    systemImage: "exclamationmark.triangle",
                    description: Text(chatsError)
                )
            } else {
                List(selection: $chatStore.selectedChatID) {
                    ForEach(chatStore.displayedChats) { chat in
                        ChatRowView(chat: chat)
                            .tag(chat.id)
                    }
                }
                .searchable(text: $chatStore.searchQuery, placement: .sidebar, prompt: "Search chats")
                .task(id: chatStore.searchQuery) {
                    try? await Task.sleep(for: .milliseconds(300))
                    await chatStore.searchChats()
                }
                .overlay {
                    if chatStore.isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
//                    else if let results = chatStore.searchResults, results.isEmpty {
//                        ContentUnavailableView.search(text: chatStore.searchQuery)
//                    }
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
}
