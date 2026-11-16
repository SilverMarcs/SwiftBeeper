#if os(iOS)
import SwiftUI

struct ReactionAccessoryBar: View {
    let message: Message
    let chat: Chat
    let environment: EnvironmentValues
    let performAction: (@escaping () -> Void) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    MessageQuickReactions(message: message, chat: chat, performAction: performAction)
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            // Six 44-point reaction targets, with the picker kept alongside.
            .frame(maxWidth: 6 * 44)

            MessageReactionPickerButton(message: message, chat: chat, performAction: performAction)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .toggleStyle(ReactionAccessoryToggleStyle())
        .buttonStyle(ReactionAccessoryButtonStyle())
        .labelStyle(.iconOnly)
        .glassEffect(.regular, in: .capsule)
        .environment(\.self, environment)
    }
}
#endif
