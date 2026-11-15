import Foundation
import Observation

/// A chat's unread mentions survive receipt updates and timeline window
/// changes. Only reaching a mention advances the captured read position.
@MainActor
@Observable
final class MentionNavigation {
    private(set) var chatID: String?
    private(set) var mentions: [Message] = []
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var revealingID: Message.ID?
    @ObservationIgnored private(set) var revealID: UUID?
    private(set) var error: String?
    private(set) var alertError: String?
    private var expectsMentions = false
    @ObservationIgnored private var after: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var revealTimeout: Task<Void, Never>?

    var isVisible: Bool {
        !mentions.isEmpty || hasMore || (expectsMentions && (isLoading || error != nil))
    }

    var isBusy: Bool { isLoading || revealingID != nil }

    func open(_ chat: Chat?) {
        generation = UUID()
        loadTask?.cancel()
        revealTimeout?.cancel()
        chatID = chat?.id
        mentions = []
        after = nil
        hasMore = false
        revealingID = nil
        revealID = nil
        error = nil
        alertError = nil
        isLoading = false
        expectsMentions = chat?.hasUnreadMention == true
        refresh()
    }

    /// Coalesce realtime changes without fetching every ordinary message.
    func receive(_ incoming: [Message]) {
        guard incoming.contains(where: { message in
            message.isPersonalMention == true || mentions.contains { $0.id == message.id }
        }) else { return }
        refresh(debounced: true)
    }

    func refresh(debounced: Bool = false, reportsErrors: Bool = false) {
        guard let chatID, revealingID == nil else { return }
        loadTask?.cancel()
        let generation = generation
        let position = after
        let requestID = UUID()
        loadID = requestID
        if !debounced { isLoading = true }
        loadTask = Task { [weak self] in
            guard let self else { return }
            if debounced {
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
            isLoading = true
            defer { if loadID == requestID { isLoading = false } }
            do {
                let page = try await APIClient.listUnreadMentions(chatID: chatID, after: position)
                guard !Task.isCancelled, self.generation == generation, after == position else { return }
                after = page.after
                mentions = page.items
                hasMore = page.hasMore
                error = nil
            } catch {
                guard !Task.isCancelled, self.generation == generation else { return }
                self.error = error.localizedDescription
                if reportsErrors { alertError = error.localizedDescription }
            }
        }
    }

    func beginReveal() -> Message? {
        guard !isBusy, let message = mentions.first else {
            if !isBusy { refresh(reportsErrors: true) }
            return nil
        }
        revealingID = message.id
        revealID = UUID()
        error = nil
        let generation = generation
        revealTimeout?.cancel()
        revealTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) }
            catch { return }
            guard let self, self.generation == generation, revealingID == message.id else { return }
            failedToReveal(message.id, error: "Couldn’t reach this mention. Tap to try again.")
        }
        return message
    }

    /// Called by the destination timeline after its scroll lands, including
    /// a thread's timeline when the mention belongs there.
    func didReveal(_ id: Message.ID) {
        guard revealingID == id, let message = mentions.first(where: { $0.id == id }) else { return }
        after = message.sortKey
        mentions.removeAll { $0.numericSortKey <= message.numericSortKey }
        revealingID = nil
        revealID = nil
        revealTimeout?.cancel()
        refresh()
    }

    /// The oldest mention came on screen without the shortcut, as when the
    /// chat opens with it in view: it's reached, so the shortcut moves on.
    /// Cheap to call for every row on every scroll frame.
    func didSee(_ id: Message.ID) {
        guard revealingID == nil, let message = mentions.first, message.id == id else { return }
        after = message.sortKey
        mentions.removeFirst()
        if mentions.isEmpty {
            // Nothing left to load means nothing to wait for either, so the
            // shortcut doesn't come back as a spinner.
            expectsMentions = false
            if hasMore { refresh() }
        }
    }

    func failedToReveal(_ id: Message.ID, error: String) {
        guard revealingID == id else { return }
        revealingID = nil
        revealID = nil
        revealTimeout?.cancel()
        self.error = error
        alertError = error
    }

    /// A redaction or edit can invalidate a queued target between its list
    /// and tap. Skip it without treating that race as a navigation failure.
    func discard(_ id: Message.ID) {
        didReveal(id)
    }

    /// An explicit Mark as Read dismisses the queue. The next incoming
    /// mention captures the room's new read position.
    func clear() {
        generation = UUID()
        loadTask?.cancel()
        revealTimeout?.cancel()
        mentions = []
        after = nil
        hasMore = false
        revealingID = nil
        revealID = nil
        isLoading = false
        expectsMentions = false
        error = nil
        alertError = nil
    }

    func cancelReveal() {
        revealingID = nil
        revealID = nil
        revealTimeout?.cancel()
    }

    func dismissError() { alertError = nil }
}
