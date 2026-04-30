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
        .defaultSize(width: 1100, height: 720)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(sessionStore)
        }
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            EasyMatrixProcess.shared.stop()
        }
    }
}

private struct BackendGate<Content: View>: View {
    let backend: EasyMatrixProcess
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch backend.state {
        case .idle, .starting:
            VStack(spacing: 16) {
                ProgressView()
                Text("Starting backend…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            content()
        case .crashed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Backend failed to start")
                    .font(.headline)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                Button("Retry") {
                    Task { await backend.start() }
                }
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
