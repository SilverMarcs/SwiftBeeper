import SwiftUI

struct ShareChatRow: View {
    let model: ShareModel
    let chat: ShareChat
    let isSelected: Bool

    var body: some View {
        HStack {
            ShareChatAvatar(model: model, chat: chat)
            Text(chat.displayTitle)
                .lineLimit(1)
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
