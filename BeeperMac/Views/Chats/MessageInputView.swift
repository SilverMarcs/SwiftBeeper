import SwiftUI

struct MessageInputView: View {
    @Environment(ChatStore.self) private var chatStore

    @State private var draftMessage = ""

    private var cannotMessage: Bool {
        chatStore.selectedChat?.cannotMessage == true
    }

    var body: some View {
        if cannotMessage {
            cannotMessageView
        } else {
            inputView
        }
    }

    private var cannotMessageView: some View {
        Text("You can't message this person")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .glassEffect()
            .padding(.horizontal)
            .padding(.vertical, 10)
    }

    private var inputView: some View {
        GlassEffectContainer {
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

            if let editingMessage = chatStore.editingMessage {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.yellow)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Editing message")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.secondary)

                        Text(editingMessage.displayText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        chatStore.cancelEditing()
                        draftMessage = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.08))
                .fixedSize(horizontal: false, vertical: true)
            }

            if let replyMessage = chatStore.replyingToMessage {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to \(replyMessage.senderDisplayName)")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.secondary)

                        Text(replyMessage.displayText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        chatStore.setReplyTo(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.background.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .bottom) {
                // Plus button
                Button {
                    // TODO: Implement attachment menu
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary, .clear)
                        .font(.largeTitle).fontWeight(.semibold)
                        .glassEffect()
                }
                .buttonStyle(.plain)
                .offset(y: -1)

                if isEditing {
                    Button {
                        chatStore.cancelEditing()
                        draftMessage = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle).fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.7), .clear)
                            .glassEffect(.regular.tint(.red.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .offset(y: -1)
                    .scaleEffect(0.9)
                }

                // Text field with glass effect
                TextField("Message", text: $draftMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 4)
                    .padding(.horizontal, 4)
                    .padding(8)
                    .glassEffect(in: .rect(cornerRadius: 16))
                    .onSubmit {
                        handleSubmit()
                    }
                    .onChange(of: chatStore.editingMessage?.id) { _, newValue in
                        if let editingMessage = chatStore.editingMessage {
                            draftMessage = editingMessage.text ?? ""
                        } else if newValue == nil {
                            draftMessage = ""
                        }
                    }

                // Send/Save button
                Button {
                    handleSubmit()
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "arrow.up")
                        .font(.system(size: 15)).fontWeight(.bold)
                }
                .opacity(0.85)
                .controlSize(.large)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
//                .disabled(sendButtonDisabled)
                .offset(y: -2)
            }
            .padding(8)
        }
        .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isEditing: Bool {
        chatStore.editingMessage != nil
    }

    private var sendButtonDisabled: Bool {
        if chatStore.isSendingMessage { return true }
        if chatStore.selectedChat == nil { return true }
        return trimmedDraftMessage.isEmpty
    }

    private var trimmedDraftMessage: String {
        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleSubmit() {
        if isEditing {
            saveEdit()
        } else {
            sendMessage()
        }
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

    private func saveEdit() {
        let text = trimmedDraftMessage

        Task {
            let didSave = await chatStore.saveEdit(newText: text)
            if didSave {
                draftMessage = ""
            }
        }
    }
}
