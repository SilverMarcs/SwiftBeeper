import Foundation

/// A bounded, disposable snapshot of server-owned chat data.
///
/// This deliberately uses the system caches directory rather than SwiftData:
/// Relay replaces these pages as units, never queries them locally, and can
/// always recover them from the server if the OS purges the file.
struct ChatCacheSnapshot: Codable, Sendable {
    var chatListsByFilterID: [String: CachedChatList]
    var timelinesByChatID: [String: CachedChatTimeline]

    nonisolated static let empty = ChatCacheSnapshot(
        chatListsByFilterID: [:],
        timelinesByChatID: [:]
    )

    nonisolated func pruned() -> ChatCacheSnapshot {
        let recentLists = chatListsByFilterID.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(12)
            .map { list in
                guard list.chats.count > 500 else { return list }
                return CachedChatList(
                    filterID: list.filterID,
                    chats: Array(list.chats.prefix(500)),
                    cursor: nil,
                    hasMore: false,
                    updatedAt: list.updatedAt
                )
            }

        let recentTimelines = timelinesByChatID.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map { timeline in
                let retainedMessages = Array(timeline.messages.suffix(100))
                return CachedChatTimeline(
                    chatID: timeline.chatID,
                    messages: retainedMessages,
                    hasMore: timeline.hasMore || retainedMessages.count < timeline.messages.count,
                    lastReadByOtherSortKey: timeline.lastReadByOtherSortKey,
                    updatedAt: timeline.updatedAt
                )
            }

        return ChatCacheSnapshot(
            chatListsByFilterID: Dictionary(
                uniqueKeysWithValues: recentLists.map { ($0.filterID, $0) }
            ),
            timelinesByChatID: Dictionary(
                uniqueKeysWithValues: recentTimelines.map { ($0.chatID, $0) }
            )
        )
    }
}

struct CachedChatList: Codable, Sendable {
    let filterID: String
    let chats: [Chat]
    let cursor: String?
    let hasMore: Bool
    let updatedAt: Date
}

struct CachedChatTimeline: Codable, Sendable {
    let chatID: String
    let messages: [Message]
    let hasMore: Bool
    let lastReadByOtherSortKey: String?
    let updatedAt: Date
}

/// Serializes cache I/O away from the main actor and coalesces all endpoints in
/// one small, atomically-replaced file. Failures are intentionally non-fatal.
actor ChatCache {
    private struct CacheFile: Codable {
        let schemaVersion: Int
        var snapshotsByEndpointIdentity: [String: ChatCacheSnapshot]
    }

    private static let schemaVersion = 1

    private let fileURL: URL
    private var loadedFile: CacheFile?

    init(fileURL: URL = URL.cachesDirectory.appending(path: "relay-chat-cache.json")) {
        self.fileURL = fileURL
    }

    func load(endpointIdentity: String) -> ChatCacheSnapshot {
        loadFileIfNeeded().snapshotsByEndpointIdentity[endpointIdentity] ?? .empty
    }

    func save(_ snapshot: ChatCacheSnapshot, endpointIdentity: String) {
        var cacheFile = loadFileIfNeeded()
        cacheFile.snapshotsByEndpointIdentity[endpointIdentity] = snapshot.pruned()
        loadedFile = cacheFile
        persist(cacheFile)
    }

    func remove(endpointIdentity: String) {
        var cacheFile = loadFileIfNeeded()
        guard cacheFile.snapshotsByEndpointIdentity.removeValue(forKey: endpointIdentity) != nil else {
            return
        }
        loadedFile = cacheFile
        persist(cacheFile)
    }

    private func loadFileIfNeeded() -> CacheFile {
        if let loadedFile {
            return loadedFile
        }

        let decoded: CacheFile?
        if let data = try? Data(contentsOf: fileURL),
           let cacheFile = try? JSONDecoder().decode(CacheFile.self, from: data),
           cacheFile.schemaVersion == Self.schemaVersion {
            decoded = cacheFile
        } else {
            decoded = nil
        }

        let result = decoded ?? CacheFile(
            schemaVersion: Self.schemaVersion,
            snapshotsByEndpointIdentity: [:]
        )
        loadedFile = result
        return result
    }

    private func persist(_ cacheFile: CacheFile) {
        guard let data = try? JSONEncoder().encode(cacheFile) else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Cache persistence must never make chat loading fail.
        }
    }
}
