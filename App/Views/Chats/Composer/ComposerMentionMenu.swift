#if os(macOS)
import SwiftUI

/// Mention suggestions as a menu at the @ in the macOS field, while the
/// field has focus. iPhone and iPad show them in
/// `ComposerMentionSuggestions` instead.
struct ComposerMentionMenu: ViewModifier {
    @Environment(InputManager.self) private var input

    let composer: Composer
    let isFocused: Bool
    let menu: MentionMenuController
    let restoreCursor: (Int) -> Void

    func body(content: Content) -> some View {
        let query = input.mentionQuery(in: composer)
        let suggestions = isFocused ? input.mentionSuggestions(in: composer) : []
        content
            .loadsMentionParticipants(for: composer)
            // The query moves the menu as the @ does; the suggestions
            // change what it lists.
            .onChange(of: query, initial: true) {
                present(suggestions, at: query)
            }
            .onChange(of: suggestions) {
                present(suggestions, at: query)
            }
            .onDisappear {
                menu.close()
            }
    }

    private func present(_ suggestions: [ChatParticipant], at query: ComposerMentionQuery?) {
        guard let query, !suggestions.isEmpty else {
            menu.close()
            return
        }
        menu.show(suggestions, anchoredAt: query.range.location, select: insertMention) {
            // Escape dismisses the query until it changes.
            composer.dismissedMentionQuery = query
        }
    }

    private func insertMention(_ participant: ChatParticipant) {
        guard let offset = input.insertMention(participant, in: composer) else { return }
        menu.close()
        restoreCursor(offset)
    }
}

extension View {
    func composerMentionMenu(
        _ composer: Composer,
        isFocused: Bool,
        menu: MentionMenuController,
        restoreCursor: @escaping (Int) -> Void
    ) -> some View {
        modifier(ComposerMentionMenu(composer: composer, isFocused: isFocused, menu: menu, restoreCursor: restoreCursor))
    }
}
#endif
