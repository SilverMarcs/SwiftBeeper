import Foundation
import Observation

@MainActor protocol RealtimeEventHandler: AnyObject {
    func realtimeDidUpsertChat(chatID: String?)
    func realtimeDidDeleteChat(chatID: String?)
    func realtimeDidUpsertMessage(chatID: String?)
    func realtimeDidDeleteMessage(chatID: String?)
    func realtimeDidUpdateReceipt(chatID: String?, entries: [[String: String]]?)
    func realtimeDidReceiveError(_ message: String)
}

@MainActor
@Observable
final class RealtimeService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketListenerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var realtimeConnectionID = UUID()
    private(set) var realtimeError: String?

    weak var eventHandler: RealtimeEventHandler?

    func start() {
        stop()
        realtimeConnectionID = UUID()

        let webSocketTask = APIClient.makeWebSocketTask()
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        let connectionID = realtimeConnectionID
        webSocketListenerTask = Task { [weak self] in
            guard let self else { return }
            await self.listenForEvents(connectionID: connectionID)
        }
    }

    func stop() {
        webSocketListenerTask?.cancel()
        reconnectTask?.cancel()

        webSocketListenerTask = nil
        reconnectTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Private

    private func listenForEvents(connectionID: UUID) async {
        while !Task.isCancelled {
            guard let webSocketTask else { return }

            do {
                let message = try await webSocketTask.receive()

                switch message {
                case .string(let text):
                    await handleWebSocketPayload(text.data(using: .utf8))
                case .data(let data):
                    await handleWebSocketPayload(data)
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled else { return }
                scheduleReconnect(connectionID: connectionID)
                return
            }
        }
    }

    private func handleWebSocketPayload(_ data: Data?) async {
        guard
            let data,
            let envelope = try? JSONDecoder().decode(WebSocketEnvelope.self, from: data)
        else { return }

        switch envelope.type {
        case "ready":
            await sendSubscriptionsAllChats()
        case "subscriptions.updated":
            break
        case "error":
            if let message = envelope.message {
                eventHandler?.realtimeDidReceiveError("Realtime error: \(message)")
            }
        case "chat.upserted":
            eventHandler?.realtimeDidUpsertChat(chatID: envelope.chatID)
        case "chat.deleted":
            eventHandler?.realtimeDidDeleteChat(chatID: envelope.chatID)
        case "message.upserted":
            eventHandler?.realtimeDidUpsertMessage(chatID: envelope.chatID)
        case "message.deleted":
            eventHandler?.realtimeDidDeleteMessage(chatID: envelope.chatID)
        case "receipt.updated":
            eventHandler?.realtimeDidUpdateReceipt(chatID: envelope.chatID, entries: envelope.entries)
        default:
            break
        }
    }

    private func sendSubscriptionsAllChats() async {
        guard let webSocketTask else { return }

        let command = SubscriptionsSetCommand(
            requestID: "subscriptions-\(UUID().uuidString)",
            chatIDs: ["*"]
        )

        do {
            let payload = try JSONEncoder().encode(command)
            try await webSocketTask.send(.data(payload))
        } catch {
            eventHandler?.realtimeDidReceiveError("Could not set realtime subscriptions: \(error.localizedDescription)")
        }
    }

    private func scheduleReconnect(connectionID: UUID) {
        guard connectionID == realtimeConnectionID else { return }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }

            self.eventHandler?.realtimeDidReceiveError("Realtime disconnected. Retrying…")

            do {
                try await Task.sleep(for: .seconds(2))
            } catch { return }

            guard !Task.isCancelled, self.realtimeConnectionID == connectionID else { return }
            self.start()
        }
    }
}

private struct WebSocketEnvelope: Decodable {
    let type: String
    let requestID: String?
    let chatID: String?
    let message: String?
    let ids: [String]?
    let entries: [[String: String]]?
}

private struct SubscriptionsSetCommand: Encodable {
    let type = "subscriptions.set"
    let requestID: String
    let chatIDs: [String]
}
