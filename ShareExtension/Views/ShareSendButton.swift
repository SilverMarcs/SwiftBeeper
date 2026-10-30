import SwiftUI

/// Send, or a spinner while sending.
struct ShareSendButton: View {
    let model: ShareModel

    var body: some View {
        if model.isSending {
            ProgressView()
        } else {
            Button("Send", systemImage: "arrow.up.circle.fill") {
                Task { await model.send() }
            }
            .labelStyle(.iconOnly)
            .font(.title)
            .buttonStyle(.borderless)
            .disabled(!model.canSend)
            .keyboardShortcut(.defaultAction)
        }
    }
}
