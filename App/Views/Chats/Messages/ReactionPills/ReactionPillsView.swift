import SwiftUI

/// The reactions below a message's bubbles, one pill per reaction. Tapping a
/// pill adds or takes back the user's own; holding one lists who reacted.
struct ReactionPillsView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The row's messages: one, or a gallery's photos and caption.
    let messages: [Message]
    let chat: Chat

    var body: some View {
        let pills = ReactionPill.pills(for: messages, selfIDs: selfIDs)
        let transition = pillTransition
        Group {
            if !pills.isEmpty {
                ReactionPillsLayout(alignsTrailing: messages.first?.isSender == true) {
                    ForEach(pills.prefix(ReactionPill.visibleLimit)) { pill in
                        ReactionPillButton(pill: pill, chat: chat)
                            .transition(transition)
                    }
                    if pills.count > ReactionPill.visibleLimit {
                        ReactionOverflowButton(
                            hiddenCount: pills.count - ReactionPill.visibleLimit,
                            message: pills[ReactionPill.visibleLimit].message,
                            chat: chat
                        )
                        .transition(transition)
                    }
                }
                // The first pill arrives with its layout.
                .transition(transition)
            }
        }
        // Scoped to the pills, outside the condition so the first pill and the
        // last one animate too. The row's own height still changes at once,
        // leaving the timeline's scroll anchoring alone. Only changes animate:
        // rows that appear with their pills, as history loads or scrolls into
        // view, show them in place.
        .animation(pillAnimation, value: pills.map(\.displayKey))
    }

    /// Pills pop in from nothing and shrink away; with Reduce Motion they fade.
    private var pillTransition: AnyTransition {
        reduceMotion ? .opacity : .scale.combined(with: .opacity)
    }

    /// Also cross-fades a pill's fill when it becomes the user's own, rolls its
    /// count, and moves the pills beside one that comes or goes.
    private var pillAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.35)
    }

    /// The user's IDs in this chat: their participant entry and their account.
    private var selfIDs: Set<String> {
        var ids = Set<String>()
        if let id = chat.participants?.items.first(where: { $0.isSelf == true })?.id { ids.insert(id) }
        if let id = chatStore.currentUserProfile?.id { ids.insert(id) }
        return ids
    }
}
