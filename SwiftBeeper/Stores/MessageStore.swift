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
    var pendingAttachment: PendingAttachment?

    var activeComposerMessage: Message? {
        editingMessage ?? replyingToMessage
    }

    var currentAccessToken = ""

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
        pendingAttachment = nil
        uploadProgress = nil
    }

    // MARK: - Loading

    func loadMessagesIfNeeded(for chatID: String) async {
        if messagesByChatID[chatID] != nil { return }
        await loadMessages(for: chatID)
    }

    func loadMessagesForChatEntry(for chatID: String) async {
        let hadCachedMessages = !(messagesByChatID[chatID] ?? []).isEmpty
        await loadMessages(for: chatID)

        guard !hadCachedMessages else { return }
        guard hasMoreMessagesByChatID[chatID] == true else { return }
        await loadOlderMessages(for: chatID)
    }

    func loadMessages(for chatID: String) async {
        guard !currentAccessToken.isEmpty else { return }

        let requestID = UUID()
        latestLoadRequestIDByChatID[chatID] = requestID
        isLoadingMessages = true
        defer {
            if latestLoadRequestIDByChatID[chatID] == requestID {
                isLoadingMessages = false
            }
        }

        do {
            let response = try await APIClient.listMessages(chatID: chatID, accessToken: currentAccessToken)
            guard latestLoadRequestIDByChatID[chatID] == requestID else { return }

            messagesError = nil
            let existingMessages = messagesByChatID[chatID] ?? []
            let refreshedMessages = refreshedMessages(
                existing: existingMessages,
                latestPage: response.items,
                chatID: chatID
            )
            if refreshedMessages != existingMessages {
                messagesByChatID[chatID] = refreshedMessages
            }
            hasMoreMessagesByChatID[chatID] = response.hasMore
            logger.debug("Loaded \(response.items.count, privacy: .public) messages for chat \(chatID, privacy: .public). Existing: \(existingMessages.count, privacy: .public). Refreshed: \(refreshedMessages.count, privacy: .public).")
        } catch {
            guard latestLoadRequestIDByChatID[chatID] == requestID else { return }
            handleMessageError(error, context: "loading messages for \(chatID)")
        }
    }

    func loadOlderMessages(for chatID: String) async {
        guard !currentAccessToken.isEmpty else { return }
        guard hasMoreMessagesByChatID[chatID] == true else { return }
        guard !isLoadingOlderMessages else { return }

        guard let oldestMessage = messagesByChatID[chatID]?.first else { return }
        let cursor = oldestMessage.sortKey

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }

        do {
            let response = try await APIClient.listMessages(
                chatID: chatID,
                cursor: cursor,
                direction: "before",
                accessToken: currentAccessToken
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
        } catch {
            handleMessageError(error, context: "loading older messages for \(chatID)")
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
        if message.localizedStandardContains("cancelled") || message.localizedStandardContains("canceled") {
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
        logDuplicateTimelineKeys(in: sorted, source: source, chatID: chatID)
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
        logDuplicateServerMessageIDs(in: messages, source: source, chatID: chatID)

        var messagesByTimelineKey: [String: Message] = [:]
        for message in messages {
            if let replaced = messagesByTimelineKey.updateValue(message, forKey: message.timelineKey), replaced.id != message.id {
                logger.debug("Normalized duplicate timeline entry in \(source, privacy: .public) for chat \(chatID, privacy: .public). sortKey: \(message.timelineKey, privacy: .public), oldID: \(replaced.id, privacy: .public), newID: \(message.id, privacy: .public)")
            }
        }

        let normalized = messagesByTimelineKey.values.sorted(by: { $0.sortKey < $1.sortKey })
        logDuplicateTimelineKeys(in: normalized, source: source, chatID: chatID)
        return normalized
    }

    private func logDuplicateServerMessageIDs(in messages: [Message], source: String, chatID: String) {
        let grouped = Dictionary(grouping: messages, by: \.id)
        for (messageID, entries) in grouped where entries.count > 1 {
            let sortKeys = entries.map(\.timelineKey).joined(separator: ", ")
            logger.warning("Duplicate message IDs in \(source, privacy: .public) for chat \(chatID, privacy: .public). messageID: \(messageID, privacy: .public), sortKeys: \(sortKeys, privacy: .public)")
        }
    }

    private func logDuplicateTimelineKeys(in messages: [Message], source: String, chatID: String) {
        let grouped = Dictionary(grouping: messages, by: \.timelineKey)
        for (timelineKey, entries) in grouped where entries.count > 1 {
            let ids = entries.map(\.id).joined(separator: ", ")
            logger.warning("Duplicate sortKeys after merge in \(source, privacy: .public) for chat \(chatID, privacy: .public). sortKey: \(timelineKey, privacy: .public), messageIDs: \(ids, privacy: .public)")
        }
    }

    // MARK: - Sending

    func clearPendingAttachment() {
        pendingAttachment = nil
        uploadProgress = nil
    }

    func sendMessage(text: String, attachment: PendingAttachment?, to chatID: String) async -> Bool {
        guard !currentAccessToken.isEmpty else { return false }

        let trimmedText = text.trimmed
        let hasText = !trimmedText.isEmpty
        let hasAttachment = attachment != nil

        guard hasText || hasAttachment else { return false }

        isSendingMessage = true
        defer {
            isSendingMessage = false
            uploadProgress = nil
        }

        let replyToID = replyingToMessage?.id

        do {
            var attachmentInput: MessageAttachmentInput?

            if let attachment {
                uploadProgress = 0
                let uploadResult = try await APIClient.uploadAsset(
                    fileData: attachment.fileData,
                    fileName: attachment.fileName,
                    mimeType: attachment.mimeType,
                    accessToken: currentAccessToken,
                    onProgress: { [weak self] progress in
                        self?.uploadProgress = progress
                    }
                )

                if let error = uploadResult.error {
                    handleMessageError("Upload failed: \(error)", context: "uploading attachment for \(chatID)")
                    return false
                }

                var size: AttachmentSizeInput?
                if let w = uploadResult.width, let h = uploadResult.height {
                    size = AttachmentSizeInput(width: w, height: h)
                }

                attachmentInput = MessageAttachmentInput(
                    uploadID: uploadResult.uploadID,
                    mimeType: attachment.mimeType,
                    fileName: attachment.fileName,
                    size: size,
                    duration: uploadResult.duration,
                    type: nil
                )
            }

            _ = try await APIClient.sendMessage(
                chatID: chatID,
                text: hasText ? trimmedText : nil,
                replyToMessageID: replyToID,
                attachment: attachmentInput,
                accessToken: currentAccessToken
            )
            replyingToMessage = nil
            pendingAttachment = nil
            messagesError = nil
            return true
        } catch {
            handleMessageError(error, context: "sending message to \(chatID)")
            return false
        }
    }

    // MARK: - Reply / Edit

    func setReplyTo(_ message: Message?) {
        if message != nil {
            editingMessage = nil
        }
        replyingToMessage = message
    }

    func canEdit(_ message: Message, in chat: Chat) -> Bool {
        guard isOutgoingMessage(message, in: chat) else { return false }
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

    private func isOutgoingMessage(_ message: Message, in chat: Chat) -> Bool {
        if let isSender = message.isSender {
            return isSender
        }

        guard let currentParticipantID = chat.participants?.items.first(where: { $0.isSelf == true })?.id else {
            return false
        }

        return message.senderID == currentParticipantID
    }

    func saveEdit(newText: String) async -> Bool {
        guard let message = editingMessage else { return false }
        guard !currentAccessToken.isEmpty else { return false }

        let trimmedText = newText.trimmed
        guard !trimmedText.isEmpty else { return false }

        isSendingMessage = true
        defer { isSendingMessage = false }

        do {
            _ = try await APIClient.editMessage(
                chatID: message.chatID,
                messageID: message.id,
                text: trimmedText,
                accessToken: currentAccessToken
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
        guard !currentAccessToken.isEmpty else { return }

        do {
            _ = try await APIClient.addReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey, accessToken: currentAccessToken)
        } catch {
            handleMessageError(error, context: "adding reaction to \(messageID)")
        }
    }

    func removeReaction(from messageID: String, in chatID: String, reactionKey: String) async {
        guard !currentAccessToken.isEmpty else { return }

        do {
            _ = try await APIClient.removeReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey, accessToken: currentAccessToken)
        } catch {
            handleMessageError(error, context: "removing reaction from \(messageID)")
        }
    }
}
