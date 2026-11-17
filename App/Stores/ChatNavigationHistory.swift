import Foundation
import Observation

/// The chats opened this session, for stepping back and forward between
/// them like a browser. Entries are chat snapshots, so a chat outside the
/// loaded sidebar (a search result or a notification tap) can be reopened.
@MainActor
@Observable
final class ChatNavigationHistory {
    /// The most entries kept on either side of the open chat.
    private static let limit = 50

    private(set) var backEntries: [Chat] = []
    private(set) var forwardEntries: [Chat] = []
    /// The open chat's entry. It stays after the selection clears, as on a
    /// filter change, so the next chat opened still records it.
    @ObservationIgnored private var current: Chat?

    var canGoBack: Bool { !backEntries.isEmpty }
    var canGoForward: Bool { !forwardEntries.isEmpty }

    /// Records a newly opened chat. Opening another chat drops the forward
    /// entries; reopening the current one only refreshes its snapshot.
    func visit(_ chat: Chat) {
        guard chat.id != current?.id else {
            current = chat
            return
        }
        if let current {
            backEntries.append(current)
            if backEntries.count > Self.limit { backEntries.removeFirst() }
        }
        forwardEntries = []
        current = chat
    }

    /// Steps back, returning the chat to open.
    func goBack() -> Chat? {
        guard let previous = backEntries.popLast() else { return nil }
        if let current { forwardEntries.append(current) }
        current = previous
        return previous
    }

    /// Steps forward, returning the chat to open.
    func goForward() -> Chat? {
        guard let next = forwardEntries.popLast() else { return nil }
        if let current { backEntries.append(current) }
        current = next
        return next
    }

    /// Forgets a deleted or left chat, merging the visits it separated.
    func remove(_ chatID: String) {
        if current?.id == chatID { current = nil }
        backEntries = Self.collapsed(backEntries.filter { $0.id != chatID }, endingBefore: current)
        forwardEntries = Self.collapsed(forwardEntries.filter { $0.id != chatID }, endingBefore: current)
    }

    func reset() {
        backEntries = []
        forwardEntries = []
        current = nil
    }

    /// Drops consecutive visits to the same chat, including a last entry that
    /// matches the open chat, so each step changes chats.
    private static func collapsed(_ entries: [Chat], endingBefore current: Chat?) -> [Chat] {
        var result: [Chat] = []
        for entry in entries where entry.id != result.last?.id {
            result.append(entry)
        }
        if let current, result.last?.id == current.id { result.removeLast() }
        return result
    }
}
