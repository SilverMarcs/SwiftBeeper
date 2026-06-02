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

        #if os(macOS)
        let webSocketTask = APIClient.makeWebSocketTask()
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        let connectionID = realtimeConnectionID
        webSocketListenerTask = Task { [weak self] in
            guard let self else { return }
            await self.listenForEvents(connectionID: connectionID)
        }
        #else
        EasyMatrixFFI.realtimeCallback = { [weak self] payload in
            guard let self else { return }
            guard let data = payload.data(using: .utf8) else { return }
            Task { @MainActor in
                await self.handleWebSocketPayload(data)
            }
        }
        
        Task { @MainActor in
            await self.handleWebSocketPayload("{\"type\":\"ready\"}".data(using: .utf8))
        }
        #endif
    }

    func stop() {
        #if os(macOS)
        webSocketListenerTask?.cancel()
        reconnectTask?.cancel()

        webSocketListenerTask = nil
        reconnectTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        #else
        EasyMatrixFFI.realtimeCallback = nil
        #endif
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
        let command = SubscriptionsSetCommand(
            requestID: "subscriptions-\(UUID().uuidString)",
            chatIDs: ["*"]
        )

        do {
            let payload = try JSONEncoder().encode(command)
            #if os(macOS)
            guard let webSocketTask else { return }
            try await webSocketTask.send(.data(payload))
            #else
            if let payloadString = String(data: payload, encoding: .utf8) {
                _ = EasyMatrixFFI.shared.sendRealtimeCommand(payloadString)
            }
            #endif
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

    enum CodingKeys: String, CodingKey {
        case type, requestID, chatID, message, ids, entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        requestID = try? container.decodeIfPresent(String.self, forKey: .requestID)
        chatID = try? container.decodeIfPresent(String.self, forKey: .chatID)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        ids = try? container.decodeIfPresent([String].self, forKey: .ids)
        // entries may contain non-string values (bools, nulls) in message events;
        // only receipt events use this field, so fall back to nil on type mismatch.
        entries = try? container.decodeIfPresent([[String: String]].self, forKey: .entries)
    }
}

private struct SubscriptionsSetCommand: Encodable {
    let type = "subscriptions.set"
    let requestID: String
    let chatIDs: [String]
}
