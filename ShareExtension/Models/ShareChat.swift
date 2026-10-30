import Foundation

/// The parts of the core's chat the share sheet shows.
struct ShareChat: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let type: String?
    let imgURL: String?
    let participants: ShareChatParticipants?

    var displayTitle: String {
        title.isEmpty ? "Untitled Chat" : title
    }

    var isGroup: Bool {
        type == "group"
    }

    /// Everyone but the user.
    var otherParticipants: [ShareChatParticipant] {
        participants?.items.filter { $0.isSelf != true } ?? []
    }

    /// The chat's own image, or the other person's in a direct chat.
    var avatarURL: String? {
        if let imgURL, !imgURL.isEmpty { return imgURL }
        guard type == "single" else { return nil }
        return otherParticipants.first?.imgURL
    }

    /// The first letters of up to two words of the title.
    var initials: String {
        let letters = displayTitle.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
