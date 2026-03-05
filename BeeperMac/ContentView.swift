//
//  ContentView.swift
//  BeeperMac
//
//  Created by Zabir Raihan on 05/03/2026.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("beeperAccessToken") private var accessToken = ""
    @AppStorage("beeperUserID") private var currentUserID = ""
    @State private var store = ChatStore()

    var body: some View {
        NavigationSplitView {
            ChatSidebarView(
                accessToken: accessToken,
                chats: store.chats,
                chatsError: store.chatsError,
                isLoadingChats: store.isLoadingChats,
                selectedChatID: $store.selectedChatID
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            ChatDetailView(
                accessToken: accessToken,
                selectedChat: store.selectedChat,
                messages: selectedMessages,
                currentUserID: currentUserID,
                isLoadingMessages: store.isLoadingMessages,
                isSendingMessage: store.isSendingMessage,
                messagesError: store.messagesError,
                sendMessage: sendCurrentChatMessage
            )
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Reload Chats") {
                    Task {
                        await store.loadChats(accessToken: accessToken)
                    }
                }
                .disabled(accessToken.isEmpty)
            }

            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .task(id: accessToken) {
            await store.updateAccessToken(accessToken)
        }
        .onChange(of: store.selectedChatID) { _, newChatID in
            guard let newChatID else {
                return
            }

            Task {
                await store.loadMessagesIfNeeded(for: newChatID, accessToken: accessToken)
            }
        }
    }

    private var selectedMessages: [Message] {
        guard let selectedChatID = store.selectedChatID else {
            return []
        }
        return store.messages(for: selectedChatID)
    }

    private func sendCurrentChatMessage(_ text: String) async -> Bool {
        guard let selectedChatID = store.selectedChatID else {
            return false
        }
        return await store.sendTextMessage(text, to: selectedChatID, accessToken: accessToken)
    }
}

#Preview {
    ContentView()
}
