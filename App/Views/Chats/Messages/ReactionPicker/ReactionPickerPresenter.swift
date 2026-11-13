import SwiftUI

struct ReactionPickerPresenter: ViewModifier {
    @State private var picker: ReactionPickerModel?

    func body(content: Content) -> some View {
        content
            .environment(\.reactionPicker, picker)
            .environment(\.showReactionPicker, ShowReactionPickerAction { message, chat in
                guard picker?.isSending != true else { return }
                picker?.cancel()
                picker = ReactionPickerModel(message: message, chat: chat)
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
