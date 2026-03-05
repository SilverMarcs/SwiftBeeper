//
//  BeeperMacApp.swift
//  BeeperMac
//
//  Created by Zabir Raihan on 05/03/2026.
//

import SwiftUI

@main
struct BeeperMacApp: App {
    @State private var sessionStore = SessionStore()
    @State private var chatStore = ChatStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionStore)
                .environment(chatStore)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(sessionStore)
        }
        #endif
    }
}
