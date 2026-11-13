import Foundation

/// Fetches the homeserver's previews of links in messages on screen, once
/// per link: concurrent requests share a fetch, and results, empty ones
/// included, stay cached so rows scrolled back into view show their card in
/// their first frame. Failed fetches are retried after a while.
@MainActor
final class LinkPreviewLoader {
    static let shared = LinkPreviewLoader()

    private enum Entry {
        case loaded(MessageLinkPreview?)
        case failed(Date)
    }

    private static let retryInterval: TimeInterval = 120
    private static let entryLimit = 1000
    private var entries: [String: Entry] = [:]
    private var fetches: [String: Task<MessageLinkPreview?, Never>] = [:]

    /// The link's loaded preview; nil when it has none or isn't loaded yet.
    func cachedPreview(for url: String) -> MessageLinkPreview? {
        guard case .loaded(let preview) = entries[url] else { return nil }
        return preview
    }

    /// Whether the link's preview needs no fetch: loaded, or failed recently.
    func isSettled(_ url: String) -> Bool {
        switch entries[url] {
        case .loaded: true
        case .failed(let date): date.timeIntervalSinceNow > -Self.retryInterval
        case nil: false
        }
    }

    /// The link's preview, fetched through the core on a cache miss. A
    /// cancelled caller stops waiting, but the fetch still finishes and
    /// fills the cache for the next one.
    func preview(for url: String) async -> MessageLinkPreview? {
        if isSettled(url) { return cachedPreview(for: url) }
        if let fetch = fetches[url] { return await fetch.value }
        let fetch = Task { [weak self] () -> MessageLinkPreview? in
            let entry: Entry
            do {
                entry = .loaded(try await APIClient.linkPreview(url: url))
            } catch {
                entry = .failed(.now)
            }
            self?.finish(url, with: entry)
            if case .loaded(let preview) = entry { return preview }
            return nil
        }
        fetches[url] = fetch
        return await fetch.value
    }

    private func finish(_ url: String, with entry: Entry) {
        fetches[url] = nil
        // Links are short strings; this only bounds a very long session.
        if entries.count >= Self.entryLimit { entries.removeAll(keepingCapacity: true) }
        entries[url] = entry
    }
}
