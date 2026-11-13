import SwiftUI

/// Reads the members of the composer's chat as soon as a mention starts
/// there, from a lone @, so the list is ready by the first letter.
///
/// Started from a change rather than `task(id:)`: on iPhone a task keyed to
/// the chat ran for the first chat opened and never again. The lookup itself
/// drops a result for a chat no longer asked for.
struct LoadMentionParticipants: ViewModifier {
    @Environment(InputManager.self) private var input
    let composer: Composer

    func body(content: Content) -> some View {
        let chatID = input.mentionQuery(in: composer) == nil ? nil : input.mentionChatID(for: composer)
        content
            .onChange(of: chatID, initial: true) { _, chatID in
                guard chatID != nil else { return }
                Task { await input.loadMentionParticipants(for: composer) }
            }
    }
}

extension View {
    func loadsMentionParticipants(for composer: Composer) -> some View {
        modifier(LoadMentionParticipants(composer: composer))
    }
}
