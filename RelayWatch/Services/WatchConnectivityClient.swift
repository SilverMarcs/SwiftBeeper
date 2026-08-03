import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityClient: NSObject, WCSessionDelegate {
    var receivedChatPage: ((WatchChatPage) -> Void)?

    private let session: WCSession
    private var activationWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        session = .default
        super.init()
    }

    func activate() async {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        applyApplicationContext(session.receivedApplicationContext)

        guard session.activationState != .activated else { return }
        await withCheckedContinuation { continuation in
            activationWaiters.append(continuation)
            if session.activationState == .activated {
                finishActivation()
            }
        }
    }

    func requestChatPage() async throws -> WatchChatPage {
        let data = try await request(["operation": "chatList"])
        return try JSONDecoder().decode(WatchChatPage.self, from: data)
    }

    func requestMessagePage(chatID: String) async throws -> WatchMessagePage {
        let data = try await request([
            "operation": "messageList",
            "chatID": chatID
        ])
        return try JSONDecoder().decode(WatchMessagePage.self, from: data)
    }

    func sendMessage(_ text: String, chatID: String) async throws -> WatchSendResult {
        let data = try await request([
            "operation": "sendMessage",
            "chatID": chatID,
            "text": text
        ])
        return try JSONDecoder().decode(WatchSendResult.self, from: data)
    }

    private func request(_ message: [String: Any]) async throws -> Data {
        if session.activationState != .activated {
            await activate()
        }
        guard session.activationState == .activated else {
            throw WatchConnectivityError.notReady
        }
        guard session.isReachable else {
            throw WatchConnectivityError.phoneUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let replyHandler: @Sendable ([String: Any]) -> Void = { response in
                if let data = response["payload"] as? Data {
                    continuation.resume(returning: data)
                } else {
                    let message = response["error"] as? String ?? "Relay returned an invalid response."
                    continuation.resume(throwing: WatchConnectivityError.phoneError(message))
                }
            }
            let errorHandler: @Sendable (Error) -> Void = { error in
                continuation.resume(throwing: error)
            }
            session.sendMessage(
                message,
                replyHandler: replyHandler,
                errorHandler: errorHandler
            )
        }
    }

    private func finishActivation() {
        let waiters = activationWaiters
        activationWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func applyApplicationContext(_ context: [String: Any]) {
        guard let data = context["chatPage"] as? Data,
              let page = try? JSONDecoder().decode(WatchChatPage.self, from: data) else {
            return
        }
        receivedChatPage?(page)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.finishActivation()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let data = applicationContext["chatPage"] as? Data
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.applyApplicationContext(["chatPage": data])
        }
    }
}

private enum WatchConnectivityError: LocalizedError {
    case notReady
    case phoneUnavailable
    case phoneError(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            "The connection to iPhone is still starting."
        case .phoneUnavailable:
            "Relay on the paired iPhone is temporarily unavailable."
        case .phoneError(let message):
            message
        }
    }
}
