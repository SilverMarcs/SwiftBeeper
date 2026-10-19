import Foundation
import Observation

/// The application owns services once. Native controllers own only presentation
/// state; Matrix's SQLite database remains the sole persistent message store.
@MainActor @Observable
final class AppContext {
    let session = SessionStore()
    let notifications = NotificationService()
    let audio = AudioPlayerService()
    let chats: ChatStore
    let composer: InputManager
    private(set) var state: ApplicationState = .starting
    @ObservationIgnored private let sessionObservation = ObservationLifetime()
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var appliedToken: String?
    private(set) var isForeground = false
    @ObservationIgnored private var pendingNotificationChatID: String?

    init() {
        URLProtocol.registerClass(MatrixURLProtocol.self)
        chats = ChatStore(realtimeService: RealtimeService(), notificationService: notifications)
        composer = InputManager(chatStore: chats)
    }

    func start() {
        guard startupTask == nil else { return }
        state = .starting
        startupTask = Task { [weak self] in
            guard let self else { return }
            defer { startupTask = nil }
            do {
                try await MatrixRuntime.shared.start()
                let result = try await APIClient.manageState()
                if result.clientState?.isLoggedIn == true, result.clientState?.isVerified == true {
                    session.accessToken = try MatrixFiles.configuration().accessToken
                    state = .ready
                } else {
                    state = .signIn(needsRecovery: result.clientState?.isLoggedIn == true)
                }
                sessionObservation.track { [weak self] in self?.sessionChanged() }
            } catch { state = .failed(error.localizedDescription) }
        }
    }

    private func sessionChanged() {
        let token = session.accessToken
        guard appliedToken != token else { return }
        if appliedToken != nil { composer.reset() }
        appliedToken = token
        if !token.isEmpty { state = .ready }
        else if state == .ready { state = .signIn(needsRecovery: false) }
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            guard let self else { return }
            await MatrixRuntime.shared.setActive(!token.isEmpty && isForeground)
            guard !Task.isCancelled else { return }
            await chats.updateAccessToken(token)
            guard !Task.isCancelled else { return }
            openPendingNotificationChat()
            await notifications.configure(signedIn: !token.isEmpty)
        }
    }

    func openNotificationChat(_ chatID: String) {
        guard !chatID.isEmpty else { return }
        pendingNotificationChatID = chatID
        openPendingNotificationChat()
    }

    private func openPendingNotificationChat() {
        guard isForeground, state == .ready, let chatID = pendingNotificationChatID else { return }
        pendingNotificationChatID = nil
        chats.openNotificationChat(chatID)
    }

    func resignActive() { isForeground = false }

    func foreground() {
        isForeground = true
        openPendingNotificationChat()
        chats.handleAppForeground()
        Task {
            await MatrixRuntime.shared.setActive(!session.accessToken.isEmpty)
            await notifications.configure(signedIn: !session.accessToken.isEmpty)
        }
    }

    func background() {
        isForeground = false
        chats.handleAppBackground()
        Task { await MatrixRuntime.shared.setActive(false) }
    }
}
