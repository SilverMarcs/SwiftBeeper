#if os(macOS)
import SwiftUI

/// Mention suggestions in a popover below the macOS field. iPhone and iPad
/// show them in `ComposerMentionSuggestions` instead.
struct ComposerMentionPopover: ViewModifier {
    @Environment(InputManager.self) private var input
    @State private var isPresented = false

    let composer: Composer
    let isFocused: Bool
    let restoreCursor: (Int) -> Void

    func body(content: Content) -> some View {
        let suggestions = input.mentionSuggestions(in: composer)
        content
            .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
                MentionSuggestionsPopover(participants: suggestions, select: insertMention)
            }
            .loadsMentionParticipants(for: composer)
            .onChange(of: suggestions, initial: true) { _, participants in
                isPresented = !participants.isEmpty && (isFocused || isPresented)
            }
            .onChange(of: isFocused) { _, focused in
                if focused { isPresented = !suggestions.isEmpty }
            }
            // Closing the popover, as by clicking elsewhere, dismisses the
            // query until it changes.
            .onChange(of: isPresented) { _, presented in
                if !presented { composer.dismissedMentionQuery = input.mentionQuery(in: composer) }
            }
            .onChange(of: composer.target) {
                isPresented = false
            }
            .onDisappear {
                isPresented = false
            }
    }

    private func insertMention(_ participant: ChatParticipant) {
        guard let offset = input.insertMention(participant, in: composer) else { return }
        isPresented = false
        restoreCursor(offset)
    }
}

extension View {
    func composerMentionPopover(_ composer: Composer, isFocused: Bool, restoreCursor: @escaping (Int) -> Void) -> some View {
        modifier(ComposerMentionPopover(composer: composer, isFocused: isFocused, restoreCursor: restoreCursor))
    }
}
#endif
