import Foundation
import Observation

#if REMOTE_ONLY
@MainActor
@Observable
final class ServerSetupModel {
    var stage: OnboardingStage = .automatic
    var remoteURL = ""
    var accessKey = ""
    var setupSecret = ""
    var isWorking = false
    var errorMessage: String?
    var startsWithRecoveryKey = false

    func configure(using serverConnection: ServerConnection) {
        guard stage == .automatic else { return }
        remoteURL = serverConnection.remoteURLString
        stage = .remoteConnection
    }

    func showRemoteConnection() {
        errorMessage = nil
        stage = .remoteConnection
    }

    func showRemoteSetup() {
        errorMessage = nil
        stage = .remoteSetup
    }

    func connectToExistingServer(
        serverConnection: ServerConnection,
        sessionStore: SessionStore,
        chatStore: ChatStore,
        notificationService: NotificationService
    ) async {
        let normalizedKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            errorMessage = "Enter the Server Access Key."
            return
        }

        await run {
            try await serverConnection.validateRemoteAccess(
                remoteURL: remoteURL,
                accessKey: normalizedKey
            )
            await notificationService.unregisterRemoteRegistration()
            await chatStore.updateAccessToken("")
            _ = try await serverConnection.updateRemoteServer(remoteURL: remoteURL)
            sessionStore.switchEndpoint(
                to: serverConnection.endpoint.identity,
                suppliedToken: normalizedKey
            )
            await chatStore.updateAccessToken(sessionStore.accessToken)
            await notificationService.syncRemoteRegistration()
            accessKey = ""
        }
    }

    func configureRemoteServer(
        serverConnection: ServerConnection,
        sessionStore: SessionStore,
        chatStore: ChatStore,
        notificationService: NotificationService
    ) async {
        let normalizedSecret = setupSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSecret.isEmpty else {
            errorMessage = "Enter the administrative setup secret."
            return
        }

        await run {
            try await serverConnection.validateRemoteManagement(
                remoteURL: remoteURL,
                setupSecret: normalizedSecret
            )
            await notificationService.unregisterRemoteRegistration()
            await chatStore.updateAccessToken("")
            _ = try await serverConnection.updateRemoteServer(
                remoteURL: remoteURL,
                manageSecret: normalizedSecret
            )
            sessionStore.switchEndpoint(to: serverConnection.endpoint.identity)

            let state = try await APIClient.manageState()
            if state.clientState?.isLoggedIn == true,
               state.clientState?.isVerified == true {
                let token = try await APIClient.mintAccessToken()
                sessionStore.accessToken = token.accessToken
                await chatStore.updateAccessToken(token.accessToken)
                await notificationService.syncRemoteRegistration()
            } else {
                startsWithRecoveryKey = state.clientState?.isLoggedIn == true
                setupSecret = ""
                stage = .beeperSignIn
            }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
#endif
