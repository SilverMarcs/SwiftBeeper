import SwiftUI

struct ChatDetailView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore

    @State private var draftMessage = ""

    var body: some View {
        if sessionStore.accessToken.isEmpty {
            TokenRequiredView(
                title: "No Chat Selected",
                systemImage: "bubble.left.and.bubble.right",
                description: "Add a token in Settings first."
            )
        } else if let selectedChat = chatStore.selectedChat {
            List(chatStore.messages(for: selectedChat.id)) { message in
                MessageRowView(
                    message: message,
                    chat: selectedChat
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
            }
            .listStyle(.plain)
            .overlay {
                if chatStore.isLoadingMessages {
                    ProgressView("Loading messages...")
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
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

                        Button("Send", systemImage: "arrow.up") {
                            let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                let didSend = await chatStore.sendTextMessage(text, to: selectedChat.id)
                                if didSend {
                                    draftMessage = ""
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .labelStyle(.iconOnly)
                        .disabled(sendButtonDisabled)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle(selectedChat.displayTitle)
        } else {
            ContentUnavailableView(
                "Pick a Chat",
                systemImage: "list.bullet",
                description: Text("Select a chat from the sidebar to view messages.")
            )
        }
    }

    private var sendButtonDisabled: Bool {
        if chatStore.isSendingMessage {
            return true
        }
        return draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
