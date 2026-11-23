import Foundation

/// How Relay draws a reaction key. A message's reactions are grouped into
/// pills by it.
enum ReactionAppearance: Hashable, Identifiable {
    /// A Unicode emoji, drawn as text.
    case emoji(String)
    /// A bridged custom emoji's image, by its mxc:// source.
    case customEmoji(source: String)
    /// A custom emoji with no known image, or a key Relay can't draw, such
    /// as a URL. All of a message's share one pill.
    case unrecognized

    init(reactionKey: String) {
        if reactionKey.hasPrefix("mxc://") {
            self = .customEmoji(source: reactionKey)
        } else if (reactionKey.hasPrefix(":") && reactionKey.hasSuffix(":"))
            || reactionKey.hasPrefix("https://")
            || reactionKey.hasPrefix("http://") {
            self = .unrecognized
        } else {
            self = .emoji(reactionKey)
        }
    }

    /// The key reacting with it sends, or nil for unrecognized reactions.
    var reactionKey: String? {
        switch self {
        case .emoji(let emoji): emoji
        case .customEmoji(let source): source
        case .unrecognized: nil
        }
    }

    var id: String { reactionKey ?? "unrecognized" }

    var isEmoji: Bool {
        if case .emoji = self { return true }
        return false
    }

    /// How VoiceOver and captions name it: the emoji, or a custom emoji's
    /// shortcode as words, such as "party parrot" for ":party_parrot:".
    func spokenName(shortcode: String?) -> String {
        if case .emoji(let emoji) = self { return emoji }
        let words = (shortcode ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            .replacing("_", with: " ")
            .replacing("-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return words.isEmpty ? "Custom emoji" : words
    }
}

extension Reaction {
    var appearance: ReactionAppearance { ReactionAppearance(reactionKey: reactionKey) }

    var spokenName: String { appearance.spokenName(shortcode: shortcode) }
}
