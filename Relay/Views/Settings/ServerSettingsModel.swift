import Foundation
import Observation

@MainActor
@Observable
final class ServerSettingsModel {
    var location: ServerLocation = .onDevice
    var remoteURL = ""
    var accessKey = ""
    var errorMessage: String?
    var savedMessage: String?

    func configure(using serverConnection: ServerConnection) {
        location = serverConnection.usesEmbeddedServer ? .onDevice : .remote
        remoteURL = serverConnection.remoteURLString
    }

    func hasChanges(using serverConnection: ServerConnection) -> Bool {
        let selectedRemoteURL = location == .remote
            ? remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
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

        let targetURL = location == .remote ? remoteURL : ""
        let suppliedKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let newEndpoint = try? ServerEndpoint.remote(from: targetURL)
        let endpointWillChange = newEndpoint != nil && newEndpoint != serverConnection.endpoint

        do {
            if location == .remote, !suppliedKey.isEmpty {
                try await serverConnection.validateRemoteAccess(
                    remoteURL: targetURL,
                    accessKey: suppliedKey
                )
            }
            if endpointWillChange {
                await notificationService.unregisterRemoteRegistration()
            }

            let changed = try await serverConnection.switchServer(remoteURL: targetURL)
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
            savedMessage = serverConnection.usesEmbeddedServer
                ? "EasyMatrix is running on this device."
                : "Connected to \(serverConnection.endpoint.baseURL.host() ?? "the remote server")."
        } catch {
            if endpointWillChange {
                await notificationService.syncRemoteRegistration()
            }
            errorMessage = error.localizedDescription
        }
    }
}
