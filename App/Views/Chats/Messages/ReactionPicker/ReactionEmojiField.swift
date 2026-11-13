#if os(iOS)
import SwiftUI

/// An input destination attached to the selected message, without a visible editor.
struct ReactionEmojiField: UIViewRepresentable {
    let model: ReactionPickerModel

    func makeUIView(context: Context) -> ReactionEmojiTextField {
        ReactionEmojiTextField()
    }

    func updateUIView(_ field: ReactionEmojiTextField, context: Context) {
        field.onSelection = model.choose
        field.onCancel = model.endChoosing
    }

    static func dismantleUIView(_ field: ReactionEmojiTextField, coordinator: ()) {
        field.onSelection = nil
        field.onCancel = nil
        field.resignFirstResponder()
    }
}
#endif
