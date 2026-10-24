import UserNotifications

extension UNUserNotificationCenter {
    /// Registration must precede delivery, including launches for a reply action.
    func registerRelayCategories() {
        let reply = UNTextInputNotificationAction(
            identifier: NotificationCategory.reply,
            title: "Reply",
            options: [.authenticationRequired],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message…"
        )
        let category = UNNotificationCategory(
            identifier: NotificationCategory.message,
            actions: [reply],
            intentIdentifiers: ["INSendMessageIntent"],
            options: []
        )
        setNotificationCategories([category])
    }

    func removeDeliveredNotifications(forChat chatID: String) async {
        let identifiers = await deliveredNotifications()
            .filter { $0.request.content.chatID == chatID }
            .map(\.request.identifier)
        removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Shows a notification reply that failed to send. Opening it restores
    /// the text as a draft in that chat.
    func addFailedReply(_ text: String, chatID: String, messageID: String?) async {
        let content = UNMutableNotificationContent()
        content.title = "Reply wasn’t sent"
        content.body = text
        content.categoryIdentifier = NotificationCategory.message
        content.threadIdentifier = chatID
        content.userInfo = ["chatID": chatID, "replyDraft": text]
        if let messageID { content.userInfo["messageID"] = messageID }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await add(request)
    }
}

extension UNNotificationContent {
    /// The chat a notification belongs to.
    nonisolated var chatID: String { userInfo["chatID"] as? String ?? threadIdentifier }

    /// The unsent text of a failed notification reply.
    nonisolated var replyDraft: String? { userInfo["replyDraft"] as? String }
}
