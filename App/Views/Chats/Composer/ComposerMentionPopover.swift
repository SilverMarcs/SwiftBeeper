import SwiftUI

/// The same mention presentation and lifecycle for every composer.
struct ComposerMentionPopover: ViewModifier {
    @Environment(InputManager.self) private var input
    @State private var isPresented = false

    let isFocused: Bool
    let restoreCursor: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
                MentionSuggestionsPopover(participants: input.mentionSuggestions, select: insertMention)
            }
            .task(id: input.mentionQuery == nil ? nil : input.mentionChatID) {
                await input.loadMentionParticipants()
            }
            .onChange(of: input.mentionSuggestions, initial: true) { _, participants in
                isPresented = !participants.isEmpty && (isFocused || isPresented)
            }
            .onChange(of: isFocused) { _, focused in
                if focused { isPresented = !input.mentionSuggestions.isEmpty }
            }
            .onChange(of: isPresented) { _, presented in
                if !presented { input.dismissedMentionQuery = input.mentionQuery }
            }
            .onChange(of: input.selectedChatID) {
                isPresented = false
                input.composerSelection = nil
                input.dismissedMentionQuery = nil
            }
            .onDisappear {
                isPresented = false
            }
    }

    private func insertMention(_ participant: ChatParticipant) {
        guard let offset = input.insertMention(participant) else { return }
        isPresented = false
        restoreCursor(offset)
    }
}

extension View {
    func composerMentionPopover(isFocused: Bool, restoreCursor: @escaping (Int) -> Void) -> some View {
        modifier(ComposerMentionPopover(isFocused: isFocused, restoreCursor: restoreCursor))
    }
}
