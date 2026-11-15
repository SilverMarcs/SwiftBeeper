import SwiftUI

/// Owns navigation independently of the timeline viewport and tracks the visible chat.
struct ChatDetailView: View {
    /// Keep lifecycle callbacks tied to this detail's navigation identity.
    let chatID: String?
    let toggleSidebar: () -> Void

    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var input
    @State private var isVisible = false
    @State private var showingChatInfo = false
    @State private var pendingDirectChat: Chat?

    var body: some View {
        let selectedChat = chatStore.selectedChat
        ChatTimelineView(source: chatStore)
            #if os(macOS)
            .navigationTitle("")
            #endif
            // The chat list uses a large title, which a pushed chat otherwise
            // starts with. Its bar then collapses to inline right after the
            // timeline's bottom-anchored first layout, and the scroll view
            // keeps its offset from the top, leaving the newest message 52pt
            // above the composer until the next touch.
            .toolbarTitleDisplayMode(.inline)
            // Messages' header: the avatar centred in the bar, the name in a
            // capsule just below it. A safe-area bar, unlike an inset, extends
            // the scroll edge effect down behind the capsule.
            .safeAreaBar(edge: .top, spacing: 0) {
                if let selectedChat {
                    ChatHeaderNameButton(title: selectedChat.displayTitle) {
                        showingChatInfo = true
                    }
                    .padding(.horizontal)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            #if os(macOS)
            // With the window toolbar's background showing, AppKit draws its
            // own frosted edge effect under the toolbar, with a hairline
            // below the capsule, whatever style is asked for. Hiding it
            // leaves the soft fade.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #endif
            .toolbar {
                if isMacOrPad {
                    ToolbarItem(placement: .navigation) {
                        Button("Toggle Sidebar", systemImage: "sidebar.left", action: toggleSidebar)
                            .help("Show or hide the chat list")
                    }
                }

                if let selectedChat {
                    ToolbarItem(placement: .principal) {
                        ChatHeaderAvatarButton(chat: selectedChat) {
                            showingChatInfo = true
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)

                    if !chatStore.unreadThreads.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            UnreadThreadsMenu()
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        ChatActionsToolbarButton(chat: selectedChat)
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
