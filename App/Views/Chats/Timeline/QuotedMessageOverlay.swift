import SwiftUI

/// A quoted message above the reply that quotes it, in the timeline's own
/// bubbles, over the blurred timeline. Tapping anywhere else closes it.
struct QuotedMessageOverlay: View {
    let context: QuotedMessageContext
    let chat: Chat
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MessageRowView(entry: context.quoted, chat: chat)
                .timelineRowPadding(startsSenderRun: false)
            if let reply = context.reply {
                MessageRowView(entry: reply, chat: chat)
                    .timelineRowPadding(startsSenderRun: true)
            }
        }
        #if os(macOS)
        .padding(.horizontal, 15)
        #else
        .padding(.horizontal, 12)
        #endif
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background {
            // Behind the rows, so only the space around the bubbles closes it.
            Button("Close", action: dismiss)
                .buttonStyle(QuotedMessageBackdropStyle())
                .keyboardShortcut(.cancelAction)
        }
        .accessibilityAddTraits(.isModal)
    }
}
