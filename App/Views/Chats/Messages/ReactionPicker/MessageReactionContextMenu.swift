import SwiftUI

/// Keeps SwiftUI's menu, preview shape, and action environments intact.
struct MessageReactionContextMenu: ViewModifier {
    @Environment(\.self) private var environment
    @State private var accessoryInstalled = false

    let message: Message
    let chat: Chat
    var galleryMessages: [Message] = []

    func body(content: Content) -> some View {
        content
            .background {
                #if os(iOS)
                ReactionContextMenuBridge(
                    message: message,
                    chat: chat,
                    environment: environment,
                    isInstalled: $accessoryInstalled
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                #endif
            }
            .contextMenu {
                MessageContextMenu(
                    message: message,
                    chat: chat,
                    galleryMessages: galleryMessages,
                    showsQuickReactions: !accessoryInstalled
                )
            }
    }
}
