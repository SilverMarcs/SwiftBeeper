import SwiftUI

struct ReactionPickerPresenter: ViewModifier {
    @State private var picker: ReactionPickerModel?
    @State private var toggleFeedback = ReactionToggleFeedback()

    func body(content: Content) -> some View {
        content
            // Here rather than on the rows: it outlives the context menus and
            // pills that toggle reactions.
            .background { ReactionToggleFeedbackPlayer(feedback: toggleFeedback) }
            .environment(\.reactionToggleFeedback, toggleFeedback)
            .environment(\.reactionPicker, picker)
            .environment(\.showReactionPicker, ShowReactionPickerAction { message, chat in
                guard picker?.isSending != true else { return }
                picker?.cancel()
                picker = ReactionPickerModel(message: message, chat: chat, toggleFeedback: toggleFeedback)
            })
            .onChange(of: picker?.isFinished) { _, isFinished in
                if isFinished == true { picker = nil }
            }
            .onDisappear {
                picker?.cancel()
                picker = nil
            }
            .alert("Couldn’t Add Reaction", isPresented: Binding(
                get: { picker?.errorMessage != nil },
                set: { if !$0 { picker?.dismissError() } }
            )) {
                Button("Retry") { picker?.retry() }
                Button("Cancel", role: .cancel) { picker?.cancel() }
            } message: {
                Text(picker?.errorMessage ?? "")
            }
    }
}

extension EnvironmentValues {
    @Entry var reactionPicker: ReactionPickerModel?
}
