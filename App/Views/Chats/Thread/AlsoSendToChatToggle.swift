import SwiftUI

/// Slack's "Also send to channel" checkbox under the thread composer.
struct AlsoSendToChatToggle: View {
    @Binding var isOn: Bool
    let chat: Chat

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label {
                Text(chat.isSingleChat ? "Also send as direct message" : "Also send to \(chat.displayTitle)")
                    .lineLimit(1)
            } icon: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
