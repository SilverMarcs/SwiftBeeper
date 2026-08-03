import Foundation

@MainActor
final class WatchCache {
    private static let maximumMessagePages = 8

    private let fileURL = URL.cachesDirectory.appending(path: "watch-chat-cache.json")

    func load() -> WatchCacheContents {
        guard let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder().decode(WatchCacheContents.self, from: data) else {
            return WatchCacheContents()
        }
        return cache
    }

    func save(_ cache: WatchCacheContents) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func trimmed(_ cache: WatchCacheContents) -> WatchCacheContents {
        let retainedIDs = cache.recentChatIDs.prefix(Self.maximumMessagePages)
        let retainedPages = Dictionary(
            uniqueKeysWithValues: retainedIDs.compactMap { chatID in
                cache.messagePages[chatID].map { (chatID, $0) }
            }
        )
        return WatchCacheContents(
            chatPage: cache.chatPage,
            messagePages: retainedPages,
            recentChatIDs: Array(retainedIDs)
        )
    }
}

struct WatchCacheContents: Codable {
    var chatPage: WatchChatPage?
    var messagePages: [String: WatchMessagePage]
    var recentChatIDs: [String]

    init(
        chatPage: WatchChatPage? = nil,
        messagePages: [String: WatchMessagePage] = [:],
        recentChatIDs: [String] = []
    ) {
        self.chatPage = chatPage
        self.messagePages = messagePages
        self.recentChatIDs = recentChatIDs
    }
}
