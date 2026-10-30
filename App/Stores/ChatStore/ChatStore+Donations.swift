import Foundation

extension ChatStore {
    /// Lets iOS suggest this chat in the share sheet.
    func donateSentMessage(to chatID: String) {
        guard let chat = chat(byID: chatID) else { return }
        let others = chat.participants?.items.filter { $0.isSelf != true } ?? []
        let recipients = others.isEmpty
            ? [(id: chat.id, name: chat.displayTitle)]
            : others.map { (id: $0.id, name: $0.displayName) }
        let imageSource = chat.imgURL ?? (chat.isGroupChat ? nil : chat.otherParticipant?.imgURL)
        Task {
            var imageData: Data?
            if let imageSource, let file = await MatrixMedia.localFile(for: imageSource) {
                imageData = try? Data(contentsOf: file)
            }
            await SentMessageDonation.donate(
                chatID: chat.id, title: chat.displayTitle, isGroup: chat.isGroupChat,
                recipients: recipients, imageData: imageData
            )
        }
    }
}
