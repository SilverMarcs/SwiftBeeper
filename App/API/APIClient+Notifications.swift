import Foundation

/// Push delivery and notification actions.
extension APIClient {
    /// Ensure personal mentions can reach the gateway ahead of room mutes.
    static func configureMentionNotifications() async throws {
        try await executeRaw("configure-mention-notifications", arguments: EmptyArguments())
    }

    /// What the notification extension needs to decrypt pushes, as JSON for
    /// the shared keychain.
    static func notificationCredentials() async throws -> Data {
        try await executeRaw("notification-credentials", arguments: EmptyArguments())
    }

    /// The account's notification preferences, as the push server expects them.
    static func pushPreferences() async throws -> Data {
        try await executeRaw("push-preferences", arguments: EmptyArguments())
    }

    /// Adds the homeserver pusher that forwards this device's pushes to the gateway.
    static func setPusher(pushkey: String, appID: String, gatewayURL: URL, deviceDisplayName: String) async throws {
        struct Arguments: Encodable {
            let pushkey: String
            let appID: String
            let gatewayURL: String
            let deviceDisplayName: String
        }
        try await executeRaw("set-pusher", arguments: Arguments(
            pushkey: pushkey, appID: appID, gatewayURL: gatewayURL.absoluteString, deviceDisplayName: deviceDisplayName
        ))
    }

    static func removePusher(pushkey: String, appID: String) async throws {
        struct Arguments: Encodable { let pushkey: String; let appID: String }
        try await executeRaw("remove-pusher", arguments: Arguments(pushkey: pushkey, appID: appID))
    }

    /// Sends a reply typed into a notification, returning once the core has sent it.
    static func sendNotificationReply(chatID: String, messageID: String?, text: String) async throws {
        struct Arguments: Encodable { let roomID: String; let eventID: String?; let text: String }
        try await executeRaw("notification-reply", arguments: Arguments(roomID: chatID, eventID: messageID, text: text))
    }
}
