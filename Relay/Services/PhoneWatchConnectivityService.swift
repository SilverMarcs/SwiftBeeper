#if os(iOS)
import Foundation
import WatchConnectivity

/// Serves small, explicitly requested pages to the paired watch. The watch
/// never receives the remote-server URL or bearer token.
@MainActor
final class PhoneWatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchConnectivityService()

    private static let chatListRequest = "chatList"
    private static let messageListRequest = "messageList"
    private static let sendMessageRequest = "sendMessage"
    private static let maximumMessageCount = 10

    private let session: WCSession
    private weak var sessionStore: SessionStore?
    private weak var serverConnection: ServerConnection?

    private override init() {
        session = .default
        super.init()
    }

    func start(sessionStore: SessionStore, serverConnection: ServerConnection) {
        self.sessionStore = sessionStore
        self.serverConnection = serverConnection

        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    /// Opportunistically keeps the watch's launch cache current whenever the
    /// phone has already refreshed the primary inbox for its own UI.
    func publish(chats: [Chat]) {
        guard session.activationState == .activated else { return }
        let page = WatchChatPage(updatedAt: .now, items: chats.map(WatchChatSummary.init))
        guard let data = try? JSONEncoder().encode(page) else { return }
        try? session.updateApplicationContext(["chatPage": data])
    }

    private func response(for operation: String, chatID: String?, text: String?) async -> [String: Any] {
        guard serverConnection?.endpoint.isEmbedded == false else {
            return ["error": "The watch companion requires Relay's remote-server edition."]
        }
        guard let accessToken = sessionStore?.accessToken, !accessToken.isEmpty else {
            return ["error": "Open Relay on iPhone and sign in first."]
        }

        do {
            switch operation {
            case Self.chatListRequest:
                let page = try await fetchChatPage(accessToken: accessToken)
                publish(page: page)
                return try encodedResponse(page)
            case Self.messageListRequest:
                guard let chatID, !chatID.isEmpty else {
                    return ["error": "The watch sent an invalid chat request."]
                }
                return try encodedResponse(
                    try await fetchMessagePage(chatID: chatID, accessToken: accessToken)
                )
            case Self.sendMessageRequest:
                guard let chatID, !chatID.isEmpty,
                      let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    return ["error": "Enter a message before sending."]
                }
                return try encodedResponse(
                    try await sendMessage(text, chatID: chatID, accessToken: accessToken)
                )
            default:
                return ["error": "The watch sent an unsupported request."]
            }
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    private func fetchChatPage(accessToken: String) async throws -> WatchChatPage {
        var components = URLComponents(
            url: APIConfiguration.baseURL.appending(path: "/v1/chats"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "inbox", value: "primary")]
        guard let url = components?.url else { throw PhoneWatchError.invalidURL }

        let request = APIClient.request(url: url, method: .get, accessToken: accessToken)
        let output: ListChatsOutput = try await APIClient.send(request)
        return WatchChatPage(updatedAt: .now, items: output.items.map(WatchChatSummary.init))
    }

    private func fetchMessagePage(chatID: String, accessToken: String) async throws -> WatchMessagePage {
        let url = APIConfiguration.baseURL
            .appending(path: "/v1/chats")
            .appending(path: chatID)
            .appending(path: "messages")
        let request = APIClient.request(url: url, method: .get, accessToken: accessToken)
        let output: ListMessagesOutput = try await APIClient.send(request)
        let messages = output.items
            .filter(\.isDisplayable)
            .sorted { $0.numericSortKey < $1.numericSortKey }
            .suffix(Self.maximumMessageCount)
            .map(WatchMessageSummary.init)
        return WatchMessagePage(chatID: chatID, updatedAt: .now, items: messages)
    }

    private func sendMessage(
        _ text: String,
        chatID: String,
        accessToken: String
    ) async throws -> WatchSendResult {
        let url = APIConfiguration.baseURL
            .appending(path: "/v1/chats")
            .appending(path: chatID)
            .appending(path: "messages")
        let request = try APIClient.request(
            url: url,
            method: .post,
            body: PhoneWatchSendMessageRequest(text: text),
            accessToken: accessToken
        )
        let output: SendMessageOutput = try await APIClient.send(request)
        return WatchSendResult(pendingMessageID: output.pendingMessageID)
    }

    private func encodedResponse<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        ["payload": try JSONEncoder().encode(value)]
    }

    private func publish(page: WatchChatPage) {
        guard let data = try? JSONEncoder().encode(page) else { return }
        try? session.updateApplicationContext(["chatPage": data])
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let operation = message["operation"] as? String ?? ""
        let chatID = message["chatID"] as? String
        let text = message["text"] as? String
        Task { @MainActor [weak self] in
            guard let self else {
                replyHandler(["error": "Relay is unavailable on iPhone."])
                return
            }
            replyHandler(await response(for: operation, chatID: chatID, text: text))
        }
    }
}

private extension WatchChatSummary {
    init(_ chat: Chat) {
        let rawAvatarURL = chat.imgURL ?? chat.otherParticipant?.imgURL
        self.init(
            id: chat.id,
            title: chat.displayTitle,
            preview: chat.previewText ?? "No messages",
            unreadCount: chat.unreadCount,
            lastActivity: chat.lastActivity,
            avatarURL: AuthenticatedImageLoader.displayURL(for: rawAvatarURL)?.absoluteString,
            isMuted: chat.isMuted
        )
    }
}

private extension WatchMessageSummary {
    init(_ message: Message) {
        self.init(
            id: message.id,
            senderName: message.senderDisplayName,
            text: message.displayText,
            timestamp: message.timestamp,
            isOutgoing: message.isSender == true
        )
    }
}

private enum PhoneWatchError: LocalizedError {
    case invalidURL

    var errorDescription: String? { "Relay could not build the watch request URL." }
}

private struct PhoneWatchSendMessageRequest: Encodable {
    let text: String
    let replyToMessageID: String? = nil
    let attachment: MessageAttachmentInput? = nil
}
#endif
