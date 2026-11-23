import Foundation

/// The message whose reactions the reaction details sheet lists.
struct ReactionDetails: Identifiable {
    var id: String { message.id }
    let message: Message
    let chat: Chat
    /// The reaction the sheet opens filtered to, or nil for all of them.
    let appearance: ReactionAppearance?
}
