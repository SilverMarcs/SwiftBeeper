import SwiftUI

/// The reactions below a message's bubbles, one pill per reaction. Tapping a
/// pill adds or takes back the user's own; holding one lists who reacted.
struct ReactionPillsView: View {
    @Environment(ChatStore.self) private var chatStore

    /// The row's messages: one, or a gallery's photos and caption.
    let messages: [Message]
    let chat: Chat

    var body: some View {
        let pills = ReactionPill.pills(for: messages, selfIDs: selfIDs)
        if !pills.isEmpty {
            ReactionPillsLayout(alignsTrailing: messages.first?.isSender == true) {
                ForEach(pills.prefix(ReactionPill.visibleLimit)) { pill in
                    ReactionPillButton(pill: pill, chat: chat)
                }
                if pills.count > ReactionPill.visibleLimit {
                    ReactionOverflowButton(
                        hiddenCount: pills.count - ReactionPill.visibleLimit,
                        message: pills[ReactionPill.visibleLimit].message,
                        chat: chat
                    )
                }
            }
        }
    }

    /// The user's IDs in this chat: their participant entry and their account.
    private var selfIDs: Set<String> {
        var ids = Set<String>()
        if let id = chat.participants?.items.first(where: { $0.isSelf == true })?.id { ids.insert(id) }
        if let id = chatStore.currentUserProfile?.id { ids.insert(id) }
        return ids
    }
}
