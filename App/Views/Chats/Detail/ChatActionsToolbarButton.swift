import SwiftUI

/// The chat's actions menu in its toolbar, which becomes Cancel while the
/// chat's composer replies to or edits a message.
struct ChatActionsToolbarButton: View {
    @Environment(InputManager.self) private var input

    let chat: Chat

    var body: some View {
        let composer = input.composer(for: ComposerTarget(chatID: chat.id))
        if composer.activeMessage != nil {
            ComposerCancelButton(composer: composer)
        } else {
            Menu("Chat Actions", systemImage: "ellipsis") {
                ChatRowActionsView(chat: chat, placement: .contextMenu)
            }
            .menuOrder(.fixed)
            .menuIndicator(.hidden)
        }
    }
}
