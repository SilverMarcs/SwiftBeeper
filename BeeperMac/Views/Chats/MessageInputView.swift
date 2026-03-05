import SwiftUI

struct MessageInputView: View {
    @Environment(ChatStore.self) private var chatStore
    
    @State private var draftMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            if let messagesError = chatStore.messagesError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(messagesError)
                        .lineLimit(2)
                }
                .font(.footnote)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.red.opacity(0.12))
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draftMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 4)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.separator, lineWidth: 1)
                    )

                Button("Send", systemImage: "arrow.up", action: sendMessage)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .labelStyle(.iconOnly)
                    .disabled(sendButtonDisabled)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private var sendButtonDisabled: Bool {
        if chatStore.isSendingMessage { return true }
        if chatStore.selectedChat == nil { return true }

        return trimmedDraftMessage.isEmpty
    }

    private var trimmedDraftMessage: String {
        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendMessage() {
        guard let chatID = chatStore.selectedChat?.id else { return }
        let text = trimmedDraftMessage

        Task {
            let didSend = await chatStore.sendTextMessage(text, to: chatID)
            if didSend {
                draftMessage = ""
            }
        }
    }
}
