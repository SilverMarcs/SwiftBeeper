//
//  ContentView.swift
//  BeeperMac
//
//  Created by Zabir Raihan on 05/03/2026.
//

import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore

    var body: some View {
        NavigationSplitView {
            ChatSidebarView()
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            ChatDetailView()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Reload Chats") {
                    Task {
                        await chatStore.loadChats()
                    }
                }
                .disabled(sessionStore.accessToken.isEmpty)
            }

            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .task(id: sessionStore.accessToken) {
            await chatStore.updateAccessToken(sessionStore.accessToken)
        }
        .onChange(of: chatStore.selectedChatID) { _, newChatID in
            guard let newChatID else {
                return
            }

            Task {
                await chatStore.loadMessagesIfNeeded(for: newChatID)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionStore())
        .environment(ChatStore())
}
