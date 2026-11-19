import SwiftUI

/// Opens the sheet listing who reacted to a message. Supplied by the timeline,
/// since the context menu that offers it dismisses on tap.
struct ShowReactionDetailsAction {
    let action: (ReactionDetails) -> Void

    /// Opens filtered to `reactionKey`, or to all reactions when it's nil.
    func callAsFunction(_ message: Message, in chat: Chat, reactionKey: String? = nil) {
        action(ReactionDetails(message: message, chat: chat, reactionKey: reactionKey))
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
