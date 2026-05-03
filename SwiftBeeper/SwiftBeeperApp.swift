import SwiftUI

@main
struct SwiftBeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionStore = SessionStore()
    @State private var chatStore = ChatStore()
    @State private var messageStore = MessageStore()
    @State private var realtimeService = RealtimeService()
    @State private var notificationService = NotificationService()
    @State private var coordinator: RealtimeCoordinator
    @State private var backend = EasyMatrixProcess.shared

    init() {
        let sessionStore = SessionStore()
        let chatStore = ChatStore()
        let messageStore = MessageStore()
        let realtimeService = RealtimeService()
        let notificationService = NotificationService()
        notificationService.messageStore = messageStore
        notificationService.chatStore = chatStore
        _sessionStore = State(initialValue: sessionStore)
        _chatStore = State(initialValue: chatStore)
        _messageStore = State(initialValue: messageStore)
        _realtimeService = State(initialValue: realtimeService)
        _notificationService = State(initialValue: notificationService)
        _coordinator = State(initialValue: RealtimeCoordinator(
            chatStore: chatStore,
            messageStore: messageStore,
            realtimeService: realtimeService,
            notificationService: notificationService
        ))
        APIClient.manageSecret = EasyMatrixProcess.shared.manageSecret
        APIClient.tokenRefresher = { [sessionStore] in
            try await sessionStore.refreshAccessToken()
        }
    }

    var body: some Scene {
        WindowGroup {
            BackendGate(backend: backend) {
                ContentView()
                    .environment(sessionStore)
                    .environment(chatStore)
                    .environment(messageStore)
                    .environment(coordinator)
                    .task {
                        await notificationService.requestAuthorization()
                    }
            }
            .frame(minWidth: 900, minHeight: 600)
            .task { await backend.start() }
        }
        .defaultSize(width: 1100, height: 750)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(sessionStore)
        }
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let backend = EasyMatrixProcess.shared
        guard backend.isRunning else { return .terminateNow }

        Task { @MainActor in
            await backend.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

private struct BackendGate<Content: View>: View {
    let backend: EasyMatrixProcess
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
        switch backend.state {
        case .idle, .starting:
            ProgressView("Starting backend")
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            Color.clear
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .stopping:
            ProgressView("Quitting")
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            Color.clear
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            content()
        case .crashed(let message):
            ContentUnavailableView {
                Label("Backend failed to start", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await backend.start() }
                }
                .controlSize(.large)
            }
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            Color.clear
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
