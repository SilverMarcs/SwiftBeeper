import Foundation
import Observation

/// Pages through one of a chat's message lists, such as its photos, newest
/// first. Lists read the local database; once it's
/// exhausted, older history can be fetched from the server into it.
@MainActor
@Observable
final class ChatMessagePager {
    typealias Fetch = (_ cursor: String?) async throws -> ChatMessagePage

    private(set) var items: [Message] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var isLoadingServerHistory = false
    private(set) var errorMessage: String?
    private var hasMore = true
    private var hasServerHistory = false
    private var cursor: String?
    private let chatID: String
    private let fetch: Fetch

    init(chatID: String, fetch: @escaping Fetch) {
        self.chatID = chatID
        self.fetch = fetch
    }

    /// Whether the local pages are exhausted but the server may hold more.
    var canLoadServerHistory: Bool {
        hasLoaded && !hasMore && hasServerHistory
    }

    var isEmpty: Bool { hasLoaded && items.isEmpty }

    /// Loads the next local page. A page can hold no matches yet have more
    /// after it, so reading continues until one adds an item.
    func loadNextPage() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var added = 0
            repeat {
                let page = try await fetch(cursor)
                let known = Set(items.map(\.id))
                let fresh = page.items.filter { !known.contains($0.id) }
                items += fresh
                added += fresh.count
                cursor = page.cursor ?? cursor
                hasMore = page.hasMore
                hasServerHistory = page.hasServerHistory
            } while added == 0 && hasMore && !Task.isCancelled
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    /// Fetches one more page of older history from the server into the
    /// local database, then reads on from the oldest item. The page may hold
    /// none of this list's kind.
    func loadServerHistory() async {
        guard canLoadServerHistory, !isLoadingServerHistory else { return }
        isLoadingServerHistory = true
        defer { isLoadingServerHistory = false }
        do {
            let output = try await APIClient.loadServerHistory(chatID: chatID)
            hasMore = true
            await loadNextPage()
            hasServerHistory = output.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
