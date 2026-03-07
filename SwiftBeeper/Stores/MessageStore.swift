import Foundation
import Observation
import OSLog

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
            logDuplicateServerMessageIDs(in: response.items, source: "loadMessages response", chatID: chatID)
            let mergedMessages = mergedMessages(
                existing: existingMessages,
                incoming: response.items,
                chatID: chatID,
                source: "loadMessages"
            )
            messagesByChatID[chatID] = mergedMessages
            hasMoreMessagesByChatID[chatID] = response.hasMore
            logger.debug("Loaded \(response.items.count, privacy: .public) messages for chat \(chatID, privacy: .public). Existing: \(existingMessages.count, privacy: .public). Merged: \(mergedMessages.count, privacy: .public).")
        } catch {
            guard latestLoadRequestIDByChatID[chatID] == requestID else { return }
            messagesError = error.localizedDescription
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
            logDuplicateServerMessageIDs(in: response.items, source: "loadOlderMessages response", chatID: chatID)
            let existingTimelineKeys = Set(existingMessages.map(\.timelineKey))
            let newMessages = response.items.filter { !existingTimelineKeys.contains($0.timelineKey) }
            let merged = mergedMessages(
                existing: existingMessages,
                incoming: newMessages,
                chatID: chatID,
                source: "loadOlderMessages"
            )
            messagesByChatID[chatID] = merged
            hasMoreMessagesByChatID[chatID] = response.hasMore
            logger.debug("Loaded \(response.items.count, privacy: .public) older messages for chat \(chatID, privacy: .public). Added: \(newMessages.count, privacy: .public). Total: \(merged.count, privacy: .public).")
        } catch {
            messagesError = error.localizedDescription
        }
    }

    // MARK: - Direct upsert / delete (from WebSocket payloads)

    func upsertMessages(_ newMessages: [Message], for chatID: String) {
        logDuplicateServerMessageIDs(in: newMessages, source: "realtime upsert", chatID: chatID)
        let payloadSummary = newMessages.map { "\($0.id)|\($0.timelineKey)|\($0.text ?? "<no-text>")" }.joined(separator: " ; ")
        let merged = mergedMessages(
            existing: messagesByChatID[chatID] ?? [],
            incoming: newMessages,
            chatID: chatID,
            source: "realtime upsert"
        )
        messagesByChatID[chatID] = merged
        logger.debug("Upserted \(newMessages.count, privacy: .public) realtime messages for chat \(chatID, privacy: .public). Total: \(merged.count, privacy: .public).")
        logger.debug("Realtime payload for chat \(chatID, privacy: .public): \(payloadSummary, privacy: .public)")
    }

    func deleteMessages(ids: [String], from chatID: String) {
        let idsToRemove = Set(ids)
        messagesByChatID[chatID]?.removeAll { idsToRemove.contains($0.id) }
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

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        Task { @MainActor in
                            self?.uploadProgress = progress
                        }
                    }
                )

                if let error = uploadResult.error {
                    messagesError = "Upload failed: \(error)"
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
            messagesError = error.localizedDescription
            return false
        }
    }

    // MARK: - Reply / Edit

    func setReplyTo(_ message: Message?) {
        replyingToMessage = message
    }

    func startEditing(_ message: Message) {
        guard message.isSender == true else { return }
        guard Date().timeIntervalSince(message.timestamp) <= 15 * 60 else { return }
        replyingToMessage = nil
        editingMessage = message
    }

    func cancelEditing() {
        editingMessage = nil
    }

    func saveEdit(newText: String) async -> Bool {
        guard let message = editingMessage else { return false }
        guard !currentAccessToken.isEmpty else { return false }

        let trimmedText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            messagesError = error.localizedDescription
            return false
        }
    }

    // MARK: - Reactions

    func addReaction(to messageID: String, in chatID: String, reactionKey: String) async {
        guard !currentAccessToken.isEmpty else { return }

        do {
            _ = try await APIClient.addReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey, accessToken: currentAccessToken)
        } catch {
            messagesError = error.localizedDescription
        }
    }

    func removeReaction(from messageID: String, in chatID: String, reactionKey: String) async {
        guard !currentAccessToken.isEmpty else { return }

        do {
            _ = try await APIClient.removeReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey, accessToken: currentAccessToken)
        } catch {
            messagesError = error.localizedDescription
        }
    }
}
