import Foundation

/// The "who or what is this" line under an info screen's title.
enum ChatInfoSubtitle {
    /// Groups: member count and network. DMs: the other person's username and network.
    static func chat(_ chat: Chat, network: String?) -> String? {
        var parts: [String] = []
        if chat.isGroupChat {
            let memberCount = chat.participants?.total ?? chat.participants?.items.count ?? 0
            if memberCount > 0 {
                // Only AttributedString applies the inflection markup.
                let members = AttributedString(localized: "^[\(memberCount) member](inflect: true)")
                parts.append(String(members.characters))
            }
        } else if let username = chat.otherParticipant?.username, username != chat.displayTitle {
            parts.append(username)
        }
        return joined(parts, network: network)
    }

    /// A person's username and network.
    static func participant(_ participant: ChatParticipant, network: String?) -> String? {
        var parts: [String] = []
        if let username = participant.username, username != participant.displayName {
            parts.append(username)
        }
        return joined(parts, network: network)
    }

    private static func joined(_ parts: [String], network: String?) -> String? {
        let parts = (parts + [network].compactMap(\.self)).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
