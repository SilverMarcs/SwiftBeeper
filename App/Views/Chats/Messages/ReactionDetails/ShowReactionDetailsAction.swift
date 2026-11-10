import SwiftUI

/// Opens the sheet listing who reacted to a message. Supplied by the timeline,
/// since the context menu that offers it dismisses on tap.
struct ShowReactionDetailsAction {
    let action: (ReactionDetails) -> Void

    func callAsFunction(_ message: Message, in chat: Chat) {
        action(ReactionDetails(message: message, chat: chat))
    }
}

extension EnvironmentValues {
    @Entry var showReactionDetails = ShowReactionDetailsAction { _ in }
}

extension View {
    /// Provides `showReactionDetails` to the timeline rows and presents its sheet.
    func showsReactionDetails() -> some View {
        modifier(ReactionDetailsPresenter())
    }
}
