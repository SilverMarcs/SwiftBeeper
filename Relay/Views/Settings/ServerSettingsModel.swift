import Foundation
import Observation

@MainActor
@Observable
final class ServerSettingsModel {
    var remoteURL = ""
    var accessKey = ""
    var errorMessage: String?
    var savedMessage: String?

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
}
