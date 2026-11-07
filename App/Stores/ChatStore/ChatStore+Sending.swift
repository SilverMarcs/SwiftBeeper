import Foundation

/// Message actions: optimistic sends through the outbox, edit rules,
/// reactions, and deletion. Drafts, replies, and edits in progress belong to
/// each conversation's `Composer`.
extension ChatStore {
    /// The open chat's optimistic rows for its main timeline.
    var timelineOutgoingMessages: [OutgoingMessage] {
        (selectedChatID.flatMap { outgoingMessagesByChatID[$0] } ?? []).filter(\.showsInMainTimeline)
    }

    // MARK: - Outbox

    /// Adds a message to the outbox synchronously so the timeline can display it
    /// before any upload or Matrix request begins.
    @discardableResult
    func sendMessage(
        text: String,
        mentions: [ComposerMention] = [],
        attachments: [PendingAttachment],
        to target: ComposerTarget,
        replyingTo replyToMessageID: String? = nil,
        alsoSendToChat: Bool = false
    ) -> OutgoingMessage? {
        let trimmedText = text.trimmed
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return nil }

        let outgoing = OutgoingMessage(
            chatID: target.chatID,
            text: trimmedText,
            mentions: mentions,
            attachments: attachments,
            replyToMessageID: replyToMessageID,
            threadRootID: target.threadRootID,
            alsoSendToChat: target.isThread && alsoSendToChat
        )
        outgoingMessagesByChatID[target.chatID, default: []].append(outgoing)
        if target.isThread {
            activeThread?.error = nil
        } else {
            messagesError = nil
        }
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
            onOutgoingMessageConfirmed?(outgoing[index].id, message)
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
                    // Every part of a thread reply stays in the thread.
                    threadRootID: outgoing.threadRootID,
                    alsoSendToChat: outgoing.alsoSendToChat,
                    attachment: attachmentInput,
                    mentions: isFirst ? outgoing.mentions : []
                )
                recordPendingMessageID(response.pendingMessageID, for: outgoing.id)
            }
            donateSentMessage(to: outgoing.chatID)
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
        var loaded = chatID == selectedChatID ? messages : []
        if let activeThread, activeThread.chatID == chatID { loaded += activeThread.replies }
        reconcileOutgoingMessages(with: loaded.filter { $0.transactionID == pendingMessageID }, chatID: chatID)
    }

    // MARK: - Edits

    /// Own messages are editable for 15 minutes, or indefinitely on networks
    /// that allow it.
    func canEdit(_ message: Message, in chat: Chat) -> Bool {
        guard !message.isDeletedMessage, message.isSender else { return false }
        if capabilities(of: chat)?.unlimitedMessageEdits == true {
            return true
        }
        return Date.now.timeIntervalSince(message.timestamp) <= 15 * 60
    }

    /// Whether replying opens the message's thread instead of quoting it.
    func repliesInThreads(in chat: Chat) -> Bool {
        capabilities(of: chat)?.threads == true
    }

    private func capabilities(of chat: Chat) -> AccountCapabilities? {
        guard let accountID = chat.accountID else { return nil }
        return connectedAccounts.first { $0.accountID == accountID }?.capabilities
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
