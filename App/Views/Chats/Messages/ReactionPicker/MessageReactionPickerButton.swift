import SwiftUI

/// Kept outside the accessory's scroll view so the picker is always reachable.
struct MessageReactionPickerButton: View {
    @Environment(\.showReactionPicker) private var showReactionPicker

    let message: Message
    let chat: Chat
    var performAction: (@escaping () -> Void) -> Void = { $0() }

    var body: some View {
        Button("More Reactions", systemImage: "plus") {
            performAction { showReactionPicker(message, in: chat) }
        }
        .accessibilityLabel("More Reactions")
        .help("More Reactions")
    }
}
