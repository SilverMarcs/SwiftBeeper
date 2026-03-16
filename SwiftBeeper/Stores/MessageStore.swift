import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class MessageStore {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SwiftBeeper", category: "MessageStore")
    private(set) var messagesByChatID: [String: [Message]] = [:]
    private(set) var hasMoreMessagesByChatID: [String: Bool] = [:]
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
        (messagesByChatID[chatID] ?? []).filter { !$0.isEmptyDeleted && !$0.isReaction && !$0.isMembershipEvent }
    }

    func message(byID messageID: String, in chatID: String) -> Message? {
        messagesByChatID[chatID]?.first(where: { $0.id == messageID })
    }

    func reset() {
        messagesByChatID = [:]
        hasMoreMessagesByChatID = [:]
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
            logger.debug("Loaded \(response.items.count, privacy: .public) messages for chat \(chatID, privacy: .public). Existing: \(existingMessages.count, privacy: .public). Refreshed: \(refreshedMessages.count, privacy: .public). New: \(newMessages.count, privacy: .public).")
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
            let normalizedResponse = normalizedMessages(response.items, source: "loadOlderMessages response", chatID: chatID)
            let newMessages = normalizedResponse.filter { !existingTimelineKeys.contains($0.timelineKey) }
            let merged = mergedMessages(
                existing: existingMessages,
                incoming: newMessages,
                chatID: chatID,
                source: "loadOlderMessages"
            )
            if merged != existingMessages {
                messagesByChatID[chatID] = merged
            }
            hasMoreMessagesByChatID[chatID] = response.hasMore
            logger.debug("Loaded \(response.items.count, privacy: .public) older messages for chat \(chatID, privacy: .public). Added: \(newMessages.count, privacy: .public). Total: \(merged.count, privacy: .public).")
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
        if isCancellationLikeError(error) {
            logger.debug("Ignoring cancelled operation while \(context, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }

        messagesError = error.localizedDescription
        logger.error("Message operation failed while \(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    private func handleMessageError(_ message: String, context: String) {
        let nsError = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
        if isCancellationLikeError(nsError) {
            logger.debug("Ignoring cancelled operation while \(context, privacy: .public): \(message, privacy: .public)")
            return
        }

        messagesError = message
        logger.error("Message operation failed while \(context, privacy: .public): \(message, privacy: .public)")
    }

    private func mergedMessages(existing: [Message], incoming: [Message], chatID: String, source: String) -> [Message] {
        var merged = Dictionary(existing.map { ($0.timelineKey, $0) }, uniquingKeysWith: { current, _ in current })
        for message in incoming {
            if let replaced = merged.updateValue(message, forKey: message.timelineKey), replaced.id != message.id {
                logger.debug("Replacing timeline entry in \(source, privacy: .public) for chat \(chatID, privacy: .public). sortKey: \(message.timelineKey, privacy: .public), oldID: \(replaced.id, privacy: .public), newID: \(message.id, privacy: .public)")
            }
        }
        let sorted = merged.values.sorted(by: { $0.sortKey < $1.sortKey })
        logDuplicates(in: sorted, keyPath: \.timelineKey, label: "sortKey", source: source, chatID: chatID)
        return sorted
    }

    private func refreshedMessages(existing: [Message], latestPage: [Message], chatID: String) -> [Message] {
        let normalizedLatestMessages = normalizedMessages(latestPage, source: "loadMessages response", chatID: chatID)
        guard let oldestLatestSortKey = normalizedLatestMessages.first?.sortKey else {
            return []
        }

        let preservedOlderMessages = existing.filter { $0.sortKey < oldestLatestSortKey }
        return mergedMessages(
            existing: preservedOlderMessages,
            incoming: normalizedLatestMessages,
            chatID: chatID,
            source: "loadMessages"
        )
    }

    private func normalizedMessages(_ messages: [Message], source: String, chatID: String) -> [Message] {
        logDuplicates(in: messages, keyPath: \.id, label: "messageID", source: source, chatID: chatID)

        var messagesByTimelineKey: [String: Message] = [:]
        for message in messages {
            if let replaced = messagesByTimelineKey.updateValue(message, forKey: message.timelineKey), replaced.id != message.id {
                logger.debug("Normalized duplicate timeline entry in \(source, privacy: .public) for chat \(chatID, privacy: .public). sortKey: \(message.timelineKey, privacy: .public), oldID: \(replaced.id, privacy: .public), newID: \(message.id, privacy: .public)")
            }
        }

        let normalized = messagesByTimelineKey.values.sorted(by: { $0.sortKey < $1.sortKey })
        logDuplicates(in: normalized, keyPath: \.timelineKey, label: "sortKey", source: source, chatID: chatID)
        return normalized
    }

    private func logDuplicates(in messages: [Message], keyPath: KeyPath<Message, String>, label: String, source: String, chatID: String) {
        let grouped = Dictionary(grouping: messages, by: { $0[keyPath: keyPath] })
        for (key, entries) in grouped where entries.count > 1 {
            let details = entries.map { $0.id == key ? $0.timelineKey : $0.id }.joined(separator: ", ")
            logger.warning("Duplicate \(label, privacy: .public) in \(source, privacy: .public) for chat \(chatID, privacy: .public). \(label, privacy: .public): \(key, privacy: .public), related: \(details, privacy: .public)")
        }
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

        if let error = uploadResult.error {
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
