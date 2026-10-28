import SwiftUI

/// Owns navigation independently of the timeline viewport and tracks the visible chat.
struct ChatDetailView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var input
    @State private var isVisible = false
    @State private var showingChatInfo = false
    @State private var profileSheetParticipant: ChatParticipant?

    var body: some View {
        let chatID = chatStore.selectedChatID
        let selectedChat = chatStore.selectedChat
        ChatTimelineView()
            #if os(macOS)
            .navigationTitle(selectedChat?.displayTitle ?? "")
            .navigationSubtitle(navigationSubtitle(for: selectedChat))
            #else
            // Keep the header outside the viewport identity used for initial scrolling.
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if let selectedChat {
                    #if os(macOS)
                    ToolbarItem(placement: .navigation) {
                        if selectedChat.isSingleChat, let other = selectedChat.otherParticipant {
                            Button {
                                profileSheetParticipant = other
                            } label: {
                                ChatAvatarView(chat: selectedChat, dimension: 28)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ChatAvatarView(chat: selectedChat, dimension: 28)
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)

                    #else
                    // iPad: avatar + name lives in the leading (navigation) slot.
                    // iPhone: stays centered in the title slot.
                    ToolbarItem(placement: isIPad ? .navigation : .principal) {
                        Button {
                            if selectedChat.isSingleChat, let other = selectedChat.otherParticipant {
                                profileSheetParticipant = other
                            } else {
                                showingChatInfo = true
                            }
                        } label: {
                            HStack {
                                ChatAvatarView(chat: selectedChat, dimension: 28)
                                Text(selectedChat.displayTitle)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: isIPhone ? 180 : nil)
                            }
                        }
                    }

                    #endif

                    ToolbarItem(placement: .primaryAction) {
                        Menu("Chat Actions", systemImage: "ellipsis") {
                            ChatRowActionsView(chat: selectedChat, placement: .contextMenu)
                        }
                        .menuOrder(.fixed)
                    }
                }
            }
            .sheet(isPresented: $showingChatInfo) {
                if let selectedChat {
                    ChatInfoSheet(chat: selectedChat)
                }
            }
            .sheet(item: $profileSheetParticipant) { participant in
                ParticipantProfileSheet(participant: participant)
            }
            .onAppear {
                isVisible = true
                chatStore.visibleChatID = chatID
            }
            .onDisappear {
                isVisible = false
                input.sendAnimator.cancelAll()
                if chatStore.visibleChatID == chatID { chatStore.visibleChatID = nil }
            }
            .onChange(of: chatID) { _, newValue in
                input.sendAnimator.cancelAll()
                if isVisible { chatStore.visibleChatID = newValue }
            }
    }

    #if os(macOS)
    private func navigationSubtitle(for chat: Chat?) -> Text {
        guard let chat, chat.isGroupChat else { return Text("") }

        let participantCount = chat.participants?.total ?? chat.participants?.items.count ?? 0
        guard participantCount > 0 else { return Text("") }

        return Text("^[\(participantCount) member](inflect: true)")
    }
    #endif
}
