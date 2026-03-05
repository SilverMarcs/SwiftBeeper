import SwiftUI

struct ChatDetailView: View {
    let accessToken: String
    let selectedChat: Chat?
    let messages: [Message]
    let currentUserID: String
    let isLoadingMessages: Bool
    let isSendingMessage: Bool
    let messagesError: String?
    let sendMessage: (String) async -> Bool

    @State private var draftMessage = ""

    var body: some View {
        if accessToken.isEmpty {
            TokenRequiredView(
                title: "No Chat Selected",
                systemImage: "bubble.left.and.bubble.right",
                description: "Add a token in Settings first."
            )
        } else if let selectedChat {
            List(messages) { message in
                MessageRowView(
                    message: message,
                    isOutgoing: isOutgoing(message),
                    senderAvatarImageURL: senderAvatarImageURL(for: message),
                    showIncomingIdentity: showIncomingIdentity
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
            }
            .listStyle(.plain)
            .overlay {
                if isLoadingMessages {
                    ProgressView("Loading messages...")
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let messagesError {
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
                                let didSend = await sendMessage(text)
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

    private var currentParticipant: ChatParticipant? {
        if let selfParticipant = selectedChat?.participants?.items.first(where: { $0.isSelf == true }) {
            return selfParticipant
        }
        if currentUserID.isEmpty == false {
            return selectedChat?.participant(with: currentUserID)
        }
        return nil
    }

    private var showIncomingIdentity: Bool {
        guard let participantCount = selectedChat?.participants?.items.count else {
            return true
        }

        return participantCount != 2
    }

    private var sendButtonDisabled: Bool {
        if isSendingMessage {
            return true
        }
        return draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func senderAvatarImageURL(for message: Message) -> String? {
        selectedChat?.participant(with: message.senderID)?.imgURL
    }

    private func isOutgoing(_ message: Message) -> Bool {
        if let isSender = message.isSender {
            return isSender
        }

        if let currentParticipant {
            return message.senderID == currentParticipant.id
        }

        if currentUserID.isEmpty == false {
            return message.senderID == currentUserID
        }

        return false
    }
}
