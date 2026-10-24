import Foundation

/// The composer's actions: optimistic sends through the outbox, edits,
/// replies, reactions, and deletion.
extension ChatStore {
    var activeComposerMessage: Message? {
        editingMessage ?? replyingToMessage
    }

    /// The open chat's optimistic rows.
    var outgoingMessages: [OutgoingMessage] {
        selectedChatID.flatMap { outgoingMessagesByChatID[$0] } ?? []
    }

    // MARK: - Outbox

    /// Adds a message to the outbox synchronously so the timeline can display it
    /// before any upload or Matrix request begins.
    @discardableResult
    func sendMessage(text: String, attachments: [PendingAttachment], to chatID: String) -> OutgoingMessage? {
        let trimmedText = text.trimmed
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return nil }

        let outgoing = OutgoingMessage(
            chatID: chatID,
            text: trimmedText,
            attachments: attachments,
            replyToMessageID: replyingToMessage?.id
        )
        outgoingMessagesByChatID[chatID, default: []].append(outgoing)
        replyingToMessage = nil
        messagesError = nil
        startSending(outgoing)
        return outgoing
    }

    func retrySending(_ messageID: OutgoingMessage.ID) {
        guard let outgoing = outgoingMessage(withID: messageID),
              case .failed = outgoing.state else { return }

        updateOutgoingMessage(messageID) { message in
            message.state = .sending
            message.pendingMessageIDs = []
            message.confirmedMessageIDs = []
        }
        startSending(outgoing)
    }

    /// Assigns each canonical message to at most one optimistic row. Transaction
    /// IDs are preferred; content matching covers an event that lands before
    /// the send call returns its transaction ID.
    func reconcileOutgoingMessages(with incoming: [Message], chatID: String) {
        guard var outgoing = outgoingMessagesByChatID[chatID], !outgoing.isEmpty else { return }

        for message in incoming where message.isSender {
            guard let index = outgoing.firstIndex(where: {
                !$0.confirmedMessageIDs.contains(message.id) && $0.matchesConfirmedMessage(message)
            }) else { continue }

            outgoing[index].confirmedMessageIDs.insert(message.id)
            #if os(iOS)
            onOutgoingMessageConfirmed?(outgoing[index].id, message)
            #endif
            if outgoing[index].confirmedMessageIDs.count >= outgoing[index].expectedConfirmationCount {
                outgoing.remove(at: index)
            }
        }

        outgoingMessagesByChatID[chatID] = outgoing.isEmpty ? nil : outgoing
    }

    private func startSending(_ outgoing: OutgoingMessage) {
        outgoingSendTasks[outgoing.id]?.cancel()
        outgoingSendTasks[outgoing.id] = Task { [weak self] in
            await self?.transmit(outgoing)
        }
    }

    /// Sends one Matrix message per attachment, or one for text alone. The
    /// text and reply ride on the first.
    private func transmit(_ outgoing: OutgoingMessage) async {
        defer { outgoingSendTasks[outgoing.id] = nil }
        let attachments: [PendingAttachment?] = outgoing.attachments.isEmpty ? [nil] : outgoing.attachments
        do {
            for (index, attachment) in attachments.enumerated() {
                let isFirst = index == 0
                let attachmentInput = try await uploadAttachment(attachment, for: outgoing.id)
                let response = try await APIClient.sendMessage(
                    chatID: outgoing.chatID,
                    text: isFirst && !outgoing.text.isEmpty ? outgoing.text : nil,
                    replyToMessageID: isFirst ? outgoing.replyToMessageID : nil,
                    attachment: attachmentInput
                )
                recordPendingMessageID(response.pendingMessageID, for: outgoing.id)
            }
        } catch {
            guard !isCancellationLikeError(error) else { return }
            updateOutgoingMessage(outgoing.id) { message in
                message.state = .failed(error.localizedDescription)
            }
        }
    }

    private func uploadAttachment(
        _ attachment: PendingAttachment?,
        for outgoingMessageID: OutgoingMessage.ID
    ) async throws -> MessageAttachmentInput? {
        guard let attachment else { return nil }
        return try await AttachmentUploader.upload(attachment) { prepared in
            // Preparation can rename or convert the file; the echo carries
            // the prepared name and type, so keep them for matching.
            updateOutgoingMessage(outgoingMessageID) { message in
                message.uploadFileNameByAttachmentID[attachment.id] = prepared.fileName
                message.uploadMimeTypeByAttachmentID[attachment.id] = prepared.mimeType
            }
        }
    }

    private func outgoingMessage(withID messageID: OutgoingMessage.ID) -> OutgoingMessage? {
        outgoingMessagesByChatID.values.lazy.flatMap { $0 }.first { $0.id == messageID }
    }

    private func updateOutgoingMessage(
        _ messageID: OutgoingMessage.ID,
        update: (inout OutgoingMessage) -> Void
    ) {
        guard let chatID = outgoingMessage(withID: messageID)?.chatID,
              var messages = outgoingMessagesByChatID[chatID],
              let index = messages.firstIndex(where: { $0.id == messageID }) else { return }

        update(&messages[index])
        outgoingMessagesByChatID[chatID] = messages
    }

    private func recordPendingMessageID(_ pendingMessageID: String, for messageID: OutgoingMessage.ID) {
        guard !pendingMessageID.isEmpty, let chatID = outgoingMessage(withID: messageID)?.chatID else { return }
        updateOutgoingMessage(messageID) { message in
            message.pendingMessageIDs.insert(pendingMessageID)
        }
        // The echo can land before the send call returns its transaction ID.
        guard chatID == selectedChatID else { return }
        reconcileOutgoingMessages(with: messages.filter { $0.transactionID == pendingMessageID }, chatID: chatID)
    }

    // MARK: - Replies and edits

    func setReplyTo(_ message: Message?) {
        if message != nil { editingMessage = nil }
        replyingToMessage = message
    }

    /// Own messages are editable for 15 minutes, or indefinitely on networks
    /// that allow it.
    func canEdit(_ message: Message, in chat: Chat) -> Bool {
        guard !message.isDeletedMessage, message.isSender else { return false }
        if let accountID = chat.accountID,
           connectedAccounts.first(where: { $0.accountID == accountID })?.capabilities.unlimitedMessageEdits == true {
            return true
        }
        return Date.now.timeIntervalSince(message.timestamp) <= 15 * 60
    }

    func startEditing(_ message: Message, in chat: Chat) {
        guard canEdit(message, in: chat) else { return }
        replyingToMessage = nil
        editingMessage = message
    }

    func cancelComposerAction() {
        replyingToMessage = nil
        editingMessage = nil
    }

    /// Returns whether the edit was saved; on failure the edit stays open.
    func saveEdit(newText: String) async -> Bool {
        guard let message = editingMessage else { return false }

        let trimmedText = newText.trimmed
        guard !trimmedText.isEmpty else { return false }

        isSavingEdit = true
        defer { isSavingEdit = false }

        do {
            try await APIClient.editMessage(chatID: message.chatID, messageID: message.id, text: trimmedText)
            editingMessage = nil
            messagesError = nil
            return true
        } catch {
            handleMessageError(error)
            return false
        }
    }

    // MARK: - Reactions and deletion

    func addReaction(to messageID: String, in chatID: String, reactionKey: String) async {
        do {
            try await APIClient.addReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey)
        } catch {
            handleMessageError(error)
        }
    }

    func removeReaction(from messageID: String, in chatID: String, reactionKey: String) async {
        do {
            try await APIClient.removeReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey)
        } catch {
            handleMessageError(error)
        }
    }

    func deleteMessage(_ messageID: String, in chatID: String) async {
        do {
            try await APIClient.deleteMessage(chatID: chatID, messageID: messageID)
        } catch {
            handleMessageError(error)
        }
    }
}
