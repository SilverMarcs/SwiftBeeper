import SwiftUI

/// Hosts the hidden emoji input behind a reaction's target while the user
/// picks an emoji for it. The timeline dims every other row meanwhile, as it
/// does for a reply or edit; tapping the timeline or leaving the keyboard
/// cancels the pick.
struct ReactionEmojiInputHost: ViewModifier {
    @Environment(\.reactionPicker) private var picker
    let messageID: String

    func body(content: Content) -> some View {
        content
            .background {
                if let picker, picker.id == messageID, picker.isChoosing {
                    #if os(macOS)
                    MacReactionEmojiInput(model: picker)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    #else
                    ReactionEmojiField(model: picker)
                        .dismissesComposerOnTap(picker.endChoosing)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    #endif
                }
            }
    }
}
