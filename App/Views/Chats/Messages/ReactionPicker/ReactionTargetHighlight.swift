import SwiftUI

/// Keeps the reaction's target visible after its context menu has dismissed.
struct ReactionTargetHighlight: ViewModifier {
    @Environment(\.reactionPicker) private var picker
    let messageID: String

    func body(content: Content) -> some View {
        content
            .overlay {
                if let picker, picker.id == messageID {
                    RoundedRectangle(cornerRadius: ChatVisualStyle.bubbleCornerRadius)
                        .strokeBorder(.tint, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
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
