import SwiftUI

/// Send, with a spinner in place of the arrow while sending. The filled
/// circle stays put so the button keeps its size and color throughout.
struct ShareSendButton: View {
    let model: ShareModel

    var body: some View {
        Button {
            Task { await model.send() }
        } label: {
            Label {
                Text(model.isSending ? "Sending" : "Send")
            } icon: {
                Image(systemName: model.isSending ? "circle.fill" : "arrow.up.circle.fill")
                    .overlay {
                        if model.isSending {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                    }
            }
        }
        .labelStyle(.iconOnly)
        .font(.title)
        .buttonStyle(.borderless)
        // Sending keeps the button enabled so it doesn't dim; `send()` ignores
        // taps until it finishes.
        .disabled(!model.canSend && !model.isSending)
        .keyboardShortcut(.defaultAction)
    }
}
