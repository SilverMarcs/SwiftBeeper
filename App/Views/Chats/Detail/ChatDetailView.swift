import SwiftUI

/// Owns navigation independently of the timeline viewport and tracks the visible chat.
struct ChatDetailView: View {
    /// Keep lifecycle callbacks tied to this detail's navigation identity.
    let chatID: String?

    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var input
    @State private var isVisible = false
    @State private var showingChatInfo = false
    @State private var pendingDirectChat: Chat?

    var body: some View {
        let selectedChat = chatStore.selectedChat
        ChatTimelineView()
            #if os(macOS)
            // Names the window for the Window menu; the toolbar shows ChatTitleButton instead.
            .navigationTitle(selectedChat?.displayTitle ?? "")
            .toolbar(removing: .title)
            #else
            // Keep the header outside the viewport identity used for initial scrolling.
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if let selectedChat {
                    #if os(macOS)
                    ToolbarItem(placement: .navigation) {
                        ChatTitleButton(chat: selectedChat) {
                            showingChatInfo = true
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)

                    #else
                    // iPad: avatar + name lives in the leading (navigation) slot.
                    // iPhone: stays centered in the title slot.
                    ToolbarItem(placement: isIPad ? .navigation : .principal) {
                        Button {
                            showingChatInfo = true
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
                        .menuIndicator(.hidden)
                    }
                }
            }
            .sheet(isPresented: $showingChatInfo, onDismiss: openPendingDirectChat) {
                if let selectedChat {
                    ChatInfoView(chat: selectedChat) { chat in
                        pendingDirectChat = chat
                    }
                }
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
                // An archived or deleted chat closes; don't leave its info open.
                if newValue == nil { showingChatInfo = false }
            }
    }

    /// Opens a member's DM once the info sheet has finished dismissing.
    private func openPendingDirectChat() {
        guard let chat = pendingDirectChat else { return }
        pendingDirectChat = nil
        chatStore.openChat(chat)
    }
}
