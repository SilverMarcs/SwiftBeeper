#if DEBUG
import SwiftUI

/// A lab chat with the same chrome as `ChatDetailView`: an inline bar with
/// the avatar, and the name's capsule in a safe-area bar below it.
struct TimelineLabChatScreen: View {
    let source: TimelineLabSource

    var body: some View {
        ChatTimelineView(source: source)
            .toolbarTitleDisplayMode(.inline)
            .safeAreaBar(edge: .top, spacing: 0) {
                ChatHeaderNameButton(title: source.chat.displayTitle) {}
                    .padding(.horizontal)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ChatHeaderAvatarButton(chat: source.chat) {}
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
#endif
