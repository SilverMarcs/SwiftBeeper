import Foundation

extension ChatStore {
    func revealNextMention() async {
        guard let target = mentionNavigation.beginReveal(), target.chatID == selectedChatID else { return }
        let chatID = target.chatID
        let revealID = mentionNavigation.revealID
        do {
            // Use the current message, so a just-redacted or edited mention
            // never jumps to an empty or unrelated bubble.
            let current = try await APIClient.getMessages(chatID: chatID, messageIDs: [target.id])
            guard selectedChatID == chatID, mentionNavigation.revealID == revealID else { return }
            guard let message = current.first, message.isPersonalMention == true, !message.isDeletedMessage else {
                mentionNavigation.discard(target.id)
                return
            }
            guard await revealMessage(message, isMention: true) else {
                mentionNavigation.failedToReveal(target.id, error: "Couldn’t show this mention. Tap to try again.")
                return
            }
        } catch {
            guard selectedChatID == chatID, mentionNavigation.revealID == revealID else { return }
            mentionNavigation.failedToReveal(target.id, error: error.localizedDescription)
            handleMessageError(error)
        }
    }
}
