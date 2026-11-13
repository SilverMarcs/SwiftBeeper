import SwiftUI

/// Closes the thread, or, while its composer replies to or edits a message,
/// leaves that instead.
struct ThreadCloseButton: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var input

    let thread: ThreadStore

    var body: some View {
        if let target = thread.composerTarget, input.composer(for: target).activeMessage != nil {
            ComposerCancelButton(composer: input.composer(for: target))
        } else {
            Button("Close Thread", systemImage: "xmark") {
                chatStore.closeThread()
            }
        }
    }
}
