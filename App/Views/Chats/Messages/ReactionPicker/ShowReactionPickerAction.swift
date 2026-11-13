import SwiftUI

/// The timeline owns presentation because its context menu dismisses on selection.
struct ShowReactionPickerAction {
    let action: (Message, Chat) -> Void

    func callAsFunction(_ message: Message, in chat: Chat) {
        action(message, chat)
    }
}

extension EnvironmentValues {
    @Entry var showReactionPicker = ShowReactionPickerAction { _, _ in }
}

extension View {
    func showsReactionPicker() -> some View {
        modifier(ReactionPickerPresenter())
    }
}
