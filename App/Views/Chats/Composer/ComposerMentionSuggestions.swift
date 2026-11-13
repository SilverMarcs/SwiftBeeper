#if os(iOS)
import SwiftUI

/// Mention suggestions on iPhone and iPad: a glass panel resting on the
/// composer bar while the keyboard is up.
///
/// The timeline lays it over its bottom edge, inside the safe area the
/// composer and keyboard leave, so it always sits just above the bar without
/// being part of it: the list growing or shrinking as a name is typed leaves
/// the composer's height, and so the timeline, where they are.
struct ComposerMentionSuggestions: View {
    @Environment(InputManager.self) private var input

    let composer: Composer

    var body: some View {
        let suggestions = input.mentionSuggestions(in: composer)
        // The panel leaves with the keyboard and returns with it.
        let isPresented = composer.isFocused && !suggestions.isEmpty
        ZStack(alignment: .bottom) {
            // Keeps the lifecycle below in place while nothing shows.
            Color.clear
                .frame(height: 0)
            if isPresented {
                MentionSuggestionsPanel(participants: suggestions, select: insertMention)
                    .padding(.bottom, Self.spacing)
            }
        }
        .loadsMentionParticipants(for: composer)
    }

    private static let spacing: CGFloat = 8

    private func insertMention(_ participant: ChatParticipant) {
        guard input.insertMention(participant, in: composer) != nil else { return }
        // The insertion placed the caret; the editor keeps the keyboard.
        composer.isFocused = true
    }
}
#endif
