#if os(macOS)
import SwiftUI

struct MacReactionEmojiInput: NSViewRepresentable {
    let model: ReactionPickerModel

    func makeNSView(context: Context) -> MacReactionEmojiTextView {
        MacReactionEmojiTextView()
    }

    func updateNSView(_ view: MacReactionEmojiTextView, context: Context) {
        view.onSelection = model.choose
        view.onCancel = model.endChoosing
    }

    static func dismantleNSView(_ view: MacReactionEmojiTextView, coordinator: ()) {
        view.stop()
    }
}
#endif
