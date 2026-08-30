import Foundation
import Observation

@MainActor
@Observable
final class ServerSettingsModel {
    var remoteURL = ""
    var accessKey = ""
    var errorMessage: String?
    var savedMessage: String?

    #if DEBUG && os(macOS)
    var pushPrivacyTestURL = ""
    var pushPrivacyTestManageSecret = ""
    var pushPrivacyTestState: PushPrivacyTestState?
    var pushPrivacyTestMessage: String?
    var isUpdatingPushPrivacyTest = false
    #endif

    func configure(using serverConnection: ServerConnection) {
        remoteURL = serverConnection.remoteURLString
    }

    func hasChanges(using serverConnection: ServerConnection) -> Bool {
        let selectedRemoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return selectedRemoteURL != serverConnection.remoteURLString
            || !accessKey.isEmpty
    }

    func apply(
        serverConnection: ServerConnection,
        sessionStore: SessionStore,
        chatStore: ChatStore,
        notificationService: NotificationService
    ) async {
        errorMessage = nil
        savedMessage = nil

        let targetURL = remoteURL
        let suppliedKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let newEndpoint = try? ServerEndpoint.remote(from: targetURL)
        let endpointWillChange = newEndpoint != nil && newEndpoint != serverConnection.endpoint

        do {
            if !suppliedKey.isEmpty {
                try await serverConnection.validateRemoteAccess(
                    remoteURL: targetURL,
                    accessKey: suppliedKey
                )
            }
            if endpointWillChange {
                await notificationService.unregisterRemoteRegistration()
            }

            let changed = try await serverConnection.updateRemoteServer(remoteURL: targetURL)
            if changed {
                await chatStore.updateAccessToken("")
                sessionStore.switchEndpoint(
                    to: serverConnection.endpoint.identity,
                    suppliedToken: suppliedKey.isEmpty ? nil : suppliedKey
                )
            } else if !suppliedKey.isEmpty {
                sessionStore.accessToken = suppliedKey
            }

            await chatStore.updateAccessToken(sessionStore.accessToken)
            await notificationService.syncRemoteRegistration()
            configure(using: serverConnection)
            accessKey = ""
            savedMessage = "Connected to \(serverConnection.endpoint.baseURL.host() ?? "the remote server")."
        } catch {
            if endpointWillChange {
                await notificationService.syncRemoteRegistration()
            }
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG && os(macOS)
    func registerPushPrivacyTest() async {
        await updatePushPrivacyTest {
            try await APIClient.registerPushPrivacyTest(
                gatewayURL: pushPrivacyTestURL,
                manageSecret: pushPrivacyTestManageSecret
            )
        }
    }

    func refreshPushPrivacyTest() async {
        await updatePushPrivacyTest {
            try await APIClient.pushPrivacyTestState(manageSecret: pushPrivacyTestManageSecret)
        }
    }

    func removePushPrivacyTest() async {
        await updatePushPrivacyTest {
            try await APIClient.removePushPrivacyTest(manageSecret: pushPrivacyTestManageSecret)
        }
    }

    private func updatePushPrivacyTest(
        operation: () async throws -> PushPrivacyTestState
    ) async {
        isUpdatingPushPrivacyTest = true
        pushPrivacyTestMessage = nil
        defer { isUpdatingPushPrivacyTest = false }
        do {
            pushPrivacyTestState = try await operation()
            pushPrivacyTestMessage = pushPrivacyTestState?.registered == true
                ? "Test pusher registered. Send a message, then refresh."
                : "Test pusher removed."
        } catch {
            pushPrivacyTestMessage = error.localizedDescription
        }
    }
    #endif
}
