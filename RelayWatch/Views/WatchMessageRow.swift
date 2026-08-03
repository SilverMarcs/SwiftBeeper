import SwiftUI

struct WatchMessageRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: WatchMessageSummary

    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer()
            }

            Text(message.text)
                .foregroundStyle(message.isOutgoing ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    message.isOutgoing
                        ? AnyShapeStyle(Color.accentColor.gradient)
                        : colorScheme == .dark
                            ? AnyShapeStyle(.background.tertiary)
                            : AnyShapeStyle(.background.secondary)
                )
                .clipShape(.rect(cornerRadius: 16))

            if !message.isOutgoing {
                Spacer()
            }
        }
    }
}
