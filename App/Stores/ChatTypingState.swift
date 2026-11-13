import Foundation
import Observation

/// Who is typing in one chat, for its chat list row. Each chat has its own
/// instance, so a change re-renders only the row that reads it.
@MainActor
@Observable
final class ChatTypingState {
    /// The other people typing, in the order the core reported them.
    private(set) var participants: [ChatParticipant] = []

    /// The chat's last-message preview when typing was last reported, so an
    /// upsert that only changes unread counts or receipts isn't mistaken for
    /// the typist's message.
    @ObservationIgnored private var baselinePreviewID: Message.ID?
    @ObservationIgnored private var expirationTask: Task<Void, Never>?

    /// Each Matrix update replaces the complete list of typists.
    func update(_ others: [ChatParticipant], previewID: Message.ID?) {
        baselinePreviewID = previewID
        guard !others.isEmpty else {
            // A stop often overtakes the typist's message in sync, as in the
            // timeline. Hold the text briefly so the old preview doesn't
            // flash back; the message's arrival ends the hold early.
            if !participants.isEmpty { expire(after: .seconds(3)) }
            return
        }
        if participants != others { participants = others }
        // The event has no expiry field. Bound its lifetime if a bridge misses
        // the stop event or sync stalls.
        expire(after: .seconds(30))
    }

    /// A typist's new message ends their typing.
    func previewChanged(to preview: Message?) {
        guard let preview, preview.id != baselinePreviewID else { return }
        let hadBaseline = baselinePreviewID != nil
        baselinePreviewID = preview.id
        // Without a baseline the preview may predate the typing.
        guard hadBaseline, !preview.isSender,
              participants.contains(where: { $0.id == preview.senderID }) else { return }
        let remaining = participants.filter { $0.id != preview.senderID }
        if remaining.isEmpty {
            clear()
        } else {
            participants = remaining
        }
    }

    func clear() {
        expirationTask?.cancel()
        expirationTask = nil
        if !participants.isEmpty { participants = [] }
    }

    /// The preview's typing text: "typing…" in a one-to-one chat, otherwise
    /// who is typing. Nil while no one is.
    func previewText(isSingleChat: Bool) -> String? {
        guard let first = participants.first else { return nil }
        if isSingleChat { return String(localized: "typing…") }
        switch participants.count {
        case 1:
            return String(localized: "\(Self.shortName(of: first)) is typing…")
        case 2:
            return String(localized: "\(Self.shortName(of: first)) and \(Self.shortName(of: participants[1])) are typing…")
        default:
            return String(localized: "Several people are typing…")
        }
    }

    /// A first name, like the preview's sender label. A typist whose member
    /// state isn't stored locally comes through named by their Matrix ID.
    private static func shortName(of participant: ChatParticipant) -> String {
        let name = participant.displayName
        guard !name.hasPrefix("@"),
              let firstName = name.split(whereSeparator: \.isWhitespace).first else {
            return String(localized: "Someone")
        }
        return String(firstName)
    }

    private func expire(after delay: Duration) {
        expirationTask?.cancel()
        expirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.clear()
        }
    }
}
