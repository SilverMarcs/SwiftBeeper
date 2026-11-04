import Foundation

extension ChatStore {
    /// Lets iOS suggest this chat in the share sheet.
    func donateSentMessage(to chatID: String) {
        guard let chat = chat(byID: chatID) else { return }
        let recipients = (chat.participants?.items ?? [])
            .filter { $0.isSelf != true }
            .map { (id: $0.id, name: $0.displayName) }
        Task {
            await SentMessageDonation.donate(
                chatID: chat.id, title: chat.displayTitle, isGroup: chat.isGroupChat,
                photo: chat.avatarURL, recipients: recipients
            )
        }
    }
}
