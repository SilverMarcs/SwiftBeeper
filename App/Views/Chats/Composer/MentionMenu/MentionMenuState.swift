#if os(macOS)
import Observation

/// What the macOS mention menu lists, and which member Return would insert.
/// The keyboard and the pointer both move the highlight, as in a menu.
@MainActor
@Observable
final class MentionMenuState {
    private(set) var participants: [ChatParticipant] = []
    var highlightedID: ChatParticipant.ID?

    var highlighted: ChatParticipant? {
        participants.first { $0.id == highlightedID }
    }

    /// Lists `participants`, highlighting the first whenever the list
    /// changes, as typing narrows it.
    func show(_ participants: [ChatParticipant]) {
        guard participants != self.participants else { return }
        self.participants = participants
        highlightedID = participants.first?.id
    }

    /// Moves the highlight `offset` rows, wrapping past either end.
    func moveHighlight(by offset: Int) {
        guard !participants.isEmpty else { return }
        let count = participants.count
        let current = participants.firstIndex { $0.id == highlightedID } ?? (offset > 0 ? -1 : 0)
        highlightedID = participants[((current + offset) % count + count) % count].id
    }
}
#endif
