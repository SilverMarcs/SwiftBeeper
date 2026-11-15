#if os(iOS)
import SwiftUI

struct ReactionAccessoryBar: View {
    let message: Message
    let chat: Chat
    let environment: EnvironmentValues
    let performAction: (@escaping () -> Void) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                MessageQuickReactions(message: message, chat: chat, performAction: performAction)
            }
            .fixedSize(horizontal: true, vertical: true)

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    MessageQuickReactions(message: message, chat: chat, performAction: performAction)
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
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
