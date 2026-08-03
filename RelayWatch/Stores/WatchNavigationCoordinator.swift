import Foundation
import Observation

@MainActor
@Observable
final class WatchNavigationCoordinator {
    static let shared = WatchNavigationCoordinator()

    private(set) var pendingChatID: String?

    private init() {}

    func open(chatID: String) {
        guard !chatID.isEmpty else { return }
        pendingChatID = chatID
    }

    func takePendingChatID() -> String? {
        defer { pendingChatID = nil }
        return pendingChatID
    }
}
