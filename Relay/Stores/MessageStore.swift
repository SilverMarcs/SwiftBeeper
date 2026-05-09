import Foundation
import Observation

@MainActor
@Observable
final class MessageStore {
    private(set) var messagesByChatID: [String: [Message]] = [:]
    private(set) var hasMoreMessagesByChatID: [String: Bool] = [:]
    /// Tracks the furthest sortKey that another participant has read, per chat.
    var lastReadByOtherSortKeyByChatID: [String: String] = [:]
    private var latestLoadRequestIDByChatID: [String: UUID] = [:]
    private(set) var isLoadingOlderMessages = false
    private(set) var isLoadingMessages = false
    private(set) var isSendingMessage = false
    var messagesError: String?
    private(set) var uploadProgress: Double?
    var replyingToMessage: Message?
    var editingMessage: Message?
    var pendingAttachments: [PendingAttachment] = []

    var activeComposerMessage: Message? {
        editingMessage ?? replyingToMessage
    }

    func messages(for chatID: String) -> [Message] {
        (messagesByChatID[chatID] ?? []).filter(\.isDisplayable)
    }

    /// Most recent locally-known message for a chat, including reactions to the user's
    /// own messages and tombstoned (empty/deleted) messages. Reactions to other people's
    /// messages and membership events are skipped — the sidebar should not surface those.
    func latestKnownMessage(for chatID: String, in chat: Chat) -> Message? {
        (messagesByChatID[chatID] ?? [])
            .filter { !$0.isMembershipEvent }
            .filter { !$0.isReaction || isReactionToOwnMessage($0, in: chat) }
            .last
    }

    /// True when `message` is a reaction whose target was sent by the local user.
    /// Returns false for non-reactions and for reactions whose target can't be found
    /// locally (we don't want to notify on third-party reactions we can't classify).
    func isReactionToOwnMessage(_ message: Message, in chat: Chat) -> Bool {
        guard message.isReaction else { return false }
        guard let targetID = message.linkedMessageID,
              let target = messagesByChatID[chat.id]?.first(where: { $0.id == targetID }) else {
            return false
        }
        return target.isOutgoing(in: chat)
    }

    func message(byID messageID: String, in chatID: String) -> Message? {
        messagesByChatID[chatID]?.first(where: { $0.id == messageID })
    }

    /// Returns true if the given outgoing message has been read/seen by the other side.
    func isReadByOther(message: Message) -> Bool {
        guard let readKey = lastReadByOtherSortKeyByChatID[message.chatID], !readKey.isEmpty else {
            return false
        }
        // Compare sort keys numerically.
        guard let msgSort = Int64(message.sortKey), let readSort = Int64(readKey) else {
            return message.sortKey <= readKey
        }
        return msgSort <= readSort
    }

    func reset() {
        messagesByChatID = [:]
        hasMoreMessagesByChatID = [:]
        lastReadByOtherSortKeyByChatID = [:]
        latestLoadRequestIDByChatID = [:]
        messagesError = nil
        replyingToMessage = nil
        editingMessage = nil
        pendingAttachments = []
        uploadProgress = nil
    }

    // MARK: - Loading

    func loadMessagesIfNeeded(for chatID: String) async {
        if messagesByChatID[chatID] != nil { return }
        await loadMessages(for: chatID)
    }

    /// Loads messages and returns any truly new messages not previously in history.
    @discardableResult
    func loadMessages(for chatID: String) async -> [Message] {
        guard !APIClient.accessToken.isEmpty else { return [] }

        let requestID = UUID()
        latestLoadRequestIDByChatID[chatID] = requestID
        isLoadingMessages = true
        defer {
            if latestLoadRequestIDByChatID[chatID] == requestID {
                isLoadingMessages = false
            }
        }

        do {
            let response = try await APIClient.listMessages(chatID: chatID)
            guard latestLoadRequestIDByChatID[chatID] == requestID else { return [] }

            messagesError = nil
            if let readKey = response.lastReadByOtherSortKey {
                lastReadByOtherSortKeyByChatID[chatID] = readKey
            }
            let existingMessages = messagesByChatID[chatID] ?? []
            let existingTimelineKeys = Set(existingMessages.map(\.timelineKey))
            let refreshedMessages = refreshedMessages(
                existing: existingMessages,
                latestPage: response.items,
                chatID: chatID
            )

            // Detect truly new messages: present in refreshed but not in existing history
            let newMessages: [Message]
            if existingMessages.isEmpty {
                // First load — nothing is "new" for notification purposes
                newMessages = []
            } else {
                newMessages = refreshedMessages.filter { !existingTimelineKeys.contains($0.timelineKey) }
            }

            if refreshedMessages != existingMessages {
                messagesByChatID[chatID] = refreshedMessages
            }
            hasMoreMessagesByChatID[chatID] = response.hasMore
            return newMessages
        } catch {
            guard latestLoadRequestIDByChatID[chatID] == requestID else { return [] }
            handleMessageError(error, context: "loading messages for \(chatID)")
            return []
        }
    }

    func hasMoreMessages(for chatID: String) -> Bool {
        hasMoreMessagesByChatID[chatID] == true
    }

    @discardableResult
    func loadOlderMessages(for chatID: String) async -> Bool {
        guard !APIClient.accessToken.isEmpty else { return false }
        guard hasMoreMessagesByChatID[chatID] == true else { return false }
        guard !isLoadingOlderMessages else { return false }

        guard let oldestMessage = messagesByChatID[chatID]?.first else { return false }
        let cursor = oldestMessage.sortKey

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }

        do {
            let response = try await APIClient.listMessages(
                chatID: chatID,
                cursor: cursor,
                direction: "before"
            )

            let existingMessages = messagesByChatID[chatID] ?? []
            let existingTimelineKeys = Set(existingMessages.map(\.timelineKey))
            let normalizedResponse = normalizedMessages(response.items)
            let newMessages = normalizedResponse.filter { !existingTimelineKeys.contains($0.timelineKey) }
            let merged = mergedMessages(
                existing: existingMessages,
                incoming: newMessages
            )
            if merged != existingMessages {
                messagesByChatID[chatID] = merged
            }
            hasMoreMessagesByChatID[chatID] = response.hasMore
            return merged != existingMessages
        } catch {
            handleMessageError(error, context: "loading older messages for \(chatID)")
            return false
        }
    }

    private func isCancellationLikeError(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        return error.localizedDescription.localizedStandardContains("cancelled")
            || error.localizedDescription.localizedStandardContains("canceled")
    }

    private func handleMessageError(_ error: any Error, context: String) {
        if isCancellationLikeError(error) { return }
        messagesError = error.localizedDescription
    }

    private func handleMessageError(_ message: String, context: String) {
        let nsError = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
        if isCancellationLikeError(nsError) { return }
        messagesError = message
    }

    private func mergedMessages(existing: [Message], incoming: [Message]) -> [Message] {
        var merged = Dictionary(existing.map { ($0.timelineKey, $0) }, uniquingKeysWith: { current, _ in current })
        for message in incoming {
            merged.updateValue(message, forKey: message.timelineKey)
        }
        let sorted = merged.values.sorted(by: { $0.numericSortKey < $1.numericSortKey })
        return sorted
    }

    private func refreshedMessages(existing: [Message], latestPage: [Message], chatID: String) -> [Message] {
        let normalizedLatestMessages = normalizedMessages(latestPage)
        guard let oldestLatestSortKey = normalizedLatestMessages.first?.sortKey else {
            return []
        }

        let oldestLatestNumeric = Int64(oldestLatestSortKey) ?? 0
        let preservedOlderMessages = existing.filter { $0.numericSortKey < oldestLatestNumeric }
        return mergedMessages(
            existing: preservedOlderMessages,
            incoming: normalizedLatestMessages
        )
    }

    private func normalizedMessages(_ messages: [Message]) -> [Message] {
        var messagesByTimelineKey: [String: Message] = [:]
        for message in messages {
            messagesByTimelineKey.updateValue(message, forKey: message.timelineKey)
        }
        return messagesByTimelineKey.values.sorted(by: { $0.numericSortKey < $1.numericSortKey })
    }

    // MARK: - Sending

    func clearPendingAttachments() {
        pendingAttachments = []
        uploadProgress = nil
    }

    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func sendMessage(text: String, attachments: [PendingAttachment], to chatID: String) async -> Bool {
        guard !APIClient.accessToken.isEmpty else { return false }

        let trimmedText = text.trimmed
        let hasText = !trimmedText.isEmpty

        guard hasText || !attachments.isEmpty else { return false }

        isSendingMessage = true
        defer {
            isSendingMessage = false
            uploadProgress = nil
        }

        let replyToID = replyingToMessage?.id

        do {
            // First message: text + reply + first attachment (if any)
            let firstAttachment = attachments.first
            let firstAttachmentInput = try await uploadAttachment(firstAttachment, chatID: chatID)

            _ = try await APIClient.sendMessage(
                chatID: chatID,
                text: hasText ? trimmedText : nil,
                replyToMessageID: replyToID,
                attachment: firstAttachmentInput
            )

            // Remaining attachments: one message each, no text or reply
            for attachment in attachments.dropFirst() {
                let attachmentInput = try await uploadAttachment(attachment, chatID: chatID)
                _ = try await APIClient.sendMessage(
                    chatID: chatID,
                    text: nil,
                    attachment: attachmentInput
                )
            }

            replyingToMessage = nil
            messagesError = nil
            return true
        } catch {
            handleMessageError(error, context: "sending message to \(chatID)")
            return false
        }
    }

    private func uploadAttachment(_ attachment: PendingAttachment?, chatID: String) async throws -> MessageAttachmentInput? {
        guard let attachment else { return nil }

        uploadProgress = 0
        let uploadResult = try await APIClient.uploadAsset(
            fileData: attachment.fileData,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            onProgress: { [weak self] progress in
                self?.uploadProgress = progress
            }
        )

        if let error = uploadResult.error, !error.isEmpty {
            handleMessageError("Upload failed: \(error)", context: "uploading attachment for \(chatID)")
            throw UploadError.serverError(error)
        }

        var size: AttachmentSizeInput?
        if let w = uploadResult.width, let h = uploadResult.height {
            size = AttachmentSizeInput(width: w, height: h)
        }

        return MessageAttachmentInput(
            uploadID: uploadResult.uploadID,
            mimeType: attachment.mimeType,
            fileName: attachment.fileName,
            size: size,
            duration: uploadResult.duration,
            type: nil
        )
    }

    private enum UploadError: Error {
        case serverError(String)
    }

    // MARK: - Reply / Edit

    func setReplyTo(_ message: Message?) {
        if message != nil {
            editingMessage = nil
        }
        replyingToMessage = message
    }

    func canEdit(_ message: Message, in chat: Chat) -> Bool {
        guard message.isOutgoing(in: chat) else { return false }
        if chat.allowsUnlimitedMessageEdits {
            return true
        }
        return Date().timeIntervalSince(message.timestamp) <= 15 * 60
    }

    func startEditing(_ message: Message, in chat: Chat) {
        guard canEdit(message, in: chat) else { return }
        replyingToMessage = nil
        editingMessage = message
    }

    func cancelEditing() {
        editingMessage = nil
    }

    func cancelComposerAction() {
        replyingToMessage = nil
        editingMessage = nil
    }

    func saveEdit(newText: String) async -> Bool {
        guard let message = editingMessage else { return false }
        guard !APIClient.accessToken.isEmpty else { return false }

        let trimmedText = newText.trimmed
        guard !trimmedText.isEmpty else { return false }

        isSendingMessage = true
        defer { isSendingMessage = false }

        do {
            _ = try await APIClient.editMessage(
                chatID: message.chatID,
                messageID: message.id,
                text: trimmedText
            )
            editingMessage = nil
            messagesError = nil
            return true
        } catch {
            handleMessageError(error, context: "editing message \(message.id)")
            return false
        }
    }

    // MARK: - Reactions

    func addReaction(to messageID: String, in chatID: String, reactionKey: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        do {
            _ = try await APIClient.addReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey)
        } catch {
            handleMessageError(error, context: "adding reaction to \(messageID)")
        }
    }

    func removeReaction(from messageID: String, in chatID: String, reactionKey: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        do {
            _ = try await APIClient.removeReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey)
        } catch {
            handleMessageError(error, context: "removing reaction from \(messageID)")
        }
    }
}
