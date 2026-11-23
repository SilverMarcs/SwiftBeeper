import SwiftUI

/// Shared by the menu palette and the iOS preview accessory. The timeline
/// continues to own the picker, feedback, and reaction requests.
struct MessageQuickReactions: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.reactionToggleFeedback) private var reactionToggleFeedback

    let message: Message
    let chat: Chat
    var performAction: (@escaping () -> Void) -> Void = { $0() }

    #if os(macOS)
    private static let commonReactions = ["👍", "❤️", "😂", "😮", "🙏"]
    #else
    private static let commonReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏", "👀", "👎"]
    #endif

    var body: some View {
        ForEach(quickReactions, id: \.self) { emoji in
            Toggle(isOn: Binding(
                get: { ownReactionKey == emoji },
                set: { isOn in performAction { setOwnReaction(isOn ? emoji : nil) } }
            )) {
                ReactionEmojiLabel(emoji: emoji)
            }
        }
    }

    private var ownReactionKey: String? {
        guard let selfID = chat.participants?.items.first(where: { $0.isSelf == true })?.id else { return nil }
        return message.reactions?.first { $0.participantID == selfID }?.reactionKey
    }

    private var quickReactions: [String] {
        #if os(macOS)
        return Self.commonReactions
        #else
        guard let ownReactionKey,
              !Self.commonReactions.contains(ownReactionKey),
              ReactionAppearance(reactionKey: ownReactionKey).isEmoji else {
            return Self.commonReactions
        }
        return Self.commonReactions + [ownReactionKey]
        #endif
    }

    private func setOwnReaction(_ newValue: String?) {
        let old = ownReactionKey
        guard old != newValue else { return }
        // Played by the timeline, since choosing dismisses this menu.
        reactionToggleFeedback?.play()
        Task {
            if let old, old != newValue {
                await chatStore.removeReaction(from: message.id, in: message.chatID, reactionKey: old)
            }
            if let newValue, newValue != old {
                await chatStore.addReaction(to: message.id, in: message.chatID, reactionKey: newValue)
            }
        }
    }
}
