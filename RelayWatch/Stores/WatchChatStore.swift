import Foundation
import Observation

@MainActor
@Observable
final class WatchChatStore {
    private(set) var chats: [WatchChatSummary]
    private(set) var messagePages: [String: WatchMessagePage]
    private(set) var isLoadingChats = false
    private(set) var loadingChatIDs: Set<String> = []
    private(set) var sendingChatIDs: Set<String> = []
    private(set) var errorMessage: String?

    @ObservationIgnored private let connectivity = WatchConnectivityClient()
    @ObservationIgnored private let cache = WatchCache()
    @ObservationIgnored private var cacheContents: WatchCacheContents

    init() {
        let cacheContents = WatchCache().load()
        self.cacheContents = cacheContents
        chats = cacheContents.chatPage?.items ?? []
        messagePages = cacheContents.messagePages
    }

    func start() async {
        connectivity.receivedChatPage = { [weak self] page in
            self?.apply(page)
        }
        await connectivity.activate()
        await refreshChats()
    }

    func refreshChats() async {
        guard !isLoadingChats else { return }
        isLoadingChats = true
        defer { isLoadingChats = false }

        do {
            apply(try await connectivity.requestChatPage())
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshMessages(for chatID: String) async {
        guard !loadingChatIDs.contains(chatID) else { return }
        loadingChatIDs.insert(chatID)
        defer { loadingChatIDs.remove(chatID) }

        do {
            let page = try await connectivity.requestMessagePage(chatID: chatID)
            messagePages[chatID] = page
            cacheContents.messagePages[chatID] = page
            cacheContents.recentChatIDs.removeAll { $0 == chatID }
            cacheContents.recentChatIDs.insert(chatID, at: 0)
            cacheContents = cache.trimmed(cacheContents)
            messagePages = cacheContents.messagePages
            cache.save(cacheContents)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage(_ text: String, to chatID: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sendingChatIDs.contains(chatID) else { return false }

        sendingChatIDs.insert(chatID)
        defer { sendingChatIDs.remove(chatID) }

        do {
            let result = try await connectivity.sendMessage(text, chatID: chatID)
            let optimisticMessage = WatchMessageSummary(
                id: result.pendingMessageID,
                senderName: "You",
                text: text,
                timestamp: .now,
                isOutgoing: true
            )
            let existingItems = messagePages[chatID]?.items ?? []
            let page = WatchMessagePage(
                chatID: chatID,
                updatedAt: .now,
                items: existingItems + [optimisticMessage]
            )
            messagePages[chatID] = page
            cacheContents.messagePages[chatID] = page
            cacheContents.recentChatIDs.removeAll { $0 == chatID }
            cacheContents.recentChatIDs.insert(chatID, at: 0)
            cacheContents = cache.trimmed(cacheContents)
            messagePages = cacheContents.messagePages
            cache.save(cacheContents)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func messages(for chatID: String) -> [WatchMessageSummary] {
        messagePages[chatID]?.items ?? []
    }

    func isLoadingMessages(for chatID: String) -> Bool {
        loadingChatIDs.contains(chatID)
    }

    func isSendingMessage(for chatID: String) -> Bool {
        sendingChatIDs.contains(chatID)
    }

    func title(for chatID: String) -> String {
        chats.first(where: { $0.id == chatID })?.title ?? "Chat"
    }

    func avatarURL(for chatID: String) -> String? {
        chats.first(where: { $0.id == chatID })?.avatarURL
    }

    private func apply(_ page: WatchChatPage) {
        guard page.updatedAt >= (cacheContents.chatPage?.updatedAt ?? .distantPast) else { return }
        chats = page.items
        cacheContents.chatPage = page
        cache.save(cacheContents)
    }
}
