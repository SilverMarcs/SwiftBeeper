import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Drives everything composer-related: the per-chat draft text, the editing /
/// reply lifecycle, attachment intake, and submitting. It sits on top of
/// `ChatStore` (which owns the actual send/edit/outbox state) so that both
/// the macOS/iPad inline composer (`MessageInputView`) and the iPhone
/// `.searchable` input can drive the exact same state through one object.
@MainActor
@Observable
final class InputManager {
    private let chatStore: ChatStore

    /// Per-chat draft text, keyed by chat ID, so switching chats keeps drafts.
    private var draftsByChatID: [String: String] = [:]
    /// Attachments belong to the chat where intake began. In particular, a
    /// PhotosPicker transfer may finish after the user has navigated elsewhere.
    private var pendingAttachmentsByChatID: [String: [PendingAttachment]] = [:]
    /// Remembers which chat owns the draft being edited so an edit finishing
    /// during navigation cannot clear the newly selected chat's draft.
    private var editingDraftChatID: String?

    /// Set true to request the inline composer grab focus on its next appear
    /// (e.g. right after tapping "Edit"). Only the inline composer observes
    /// this — the iPhone `.searchable` field manages its own presentation.
    var pendingFocus = false

    /// Mirrors the inline composer's `FocusState` (set by `MessageInputView`)
    /// so the iPad chat detail — which owns the scroll proxy — can scroll to
    /// the bottom when the keyboard comes up.
    var isComposerFocused = false

    init(chatStore: ChatStore) {
        self.chatStore = chatStore
    }

    // MARK: - Draft text

    var selectedChatID: String? { chatStore.selectedChatID }

    var draft: String {
        get {
            guard let selectedChatID else { return "" }
            return draftsByChatID[selectedChatID] ?? ""
        }
        set {
            guard let selectedChatID else { return }
            draftsByChatID[selectedChatID] = newValue
        }
    }

    /// Binding for text fields (`TextField`, `.searchable`).
    var draftBinding: Binding<String> {
        Binding(get: { self.draft }, set: { self.draft = $0 })
    }

    var trimmedDraft: String { draft.trimmed }

    private func clearDraft(for chatID: String) {
        draftsByChatID[chatID] = nil
    }

    // MARK: - Derived composer state

    var cannotMessage: Bool { chatStore.selectedChat?.cannotMessage == true }

    var isEditing: Bool { chatStore.editingMessage != nil }

    var hasActiveComposerAction: Bool { chatStore.activeComposerMessage != nil }

    var isSavingEdit: Bool { chatStore.isSavingEdit }

    var pendingAttachments: [PendingAttachment] {
        guard let selectedChatID else { return [] }
        return pendingAttachmentsByChatID[selectedChatID] ?? []
    }

    var messageFieldPrompt: String {
        if isEditing { return "Edit message" }
        if chatStore.replyingToMessage != nil { return "Reply message" }
        return "Message"
    }

    var sendButtonDisabled: Bool {
        if chatStore.selectedChat == nil { return true }
        if isEditing && chatStore.isSavingEdit { return true }
        return trimmedDraft.isEmpty && pendingAttachments.isEmpty
    }

    var mostRecentEditableOutgoingMessage: Message? {
        guard let selectedChat = chatStore.selectedChat else { return nil }
        return chatStore.messages(for: selectedChat.id).last { message in
            chatStore.canEdit(message, in: selectedChat)
        }
    }

    // MARK: - Editing / reply lifecycle

    /// Pull the message text into the draft when editing begins, and clear the
    /// draft when the composer action ends. Call from an `.onChange` on
    /// `chatStore.editingMessage?.id` so both platforms stay in sync.
    func editingMessageDidChange() {
        if let editingMessage = chatStore.editingMessage {
            editingDraftChatID = editingMessage.chatID
            draftsByChatID[editingMessage.chatID] = editingMessage.text ?? ""
        } else if let editingDraftChatID {
            draftsByChatID[editingDraftChatID] = nil
            self.editingDraftChatID = nil
        }
    }

    func startEditing(_ message: Message, in chat: Chat) {
        withAnimation {
            chatStore.startEditing(message, in: chat)
        }
        pendingFocus = true
    }

    func editMostRecentOutgoingMessage() {
        guard let message = mostRecentEditableOutgoingMessage,
              let chat = chatStore.selectedChat else { return }
        startEditing(message, in: chat)
    }

    func cancelComposerAction() {
        withAnimation {
            let editingChatID = chatStore.editingMessage?.chatID
            chatStore.cancelComposerAction()
            if let editingChatID {
                clearDraft(for: editingChatID)
                editingDraftChatID = nil
            }
        }
    }

    // MARK: - Submit

    func handleSubmit() {
        if isEditing {
            saveEdit()
        } else {
            sendMessage()
        }
    }

    private func sendMessage() {
        guard let chatID = chatStore.selectedChat?.id else { return }
        let text = trimmedDraft
        let attachments = pendingAttachments

        guard !text.isEmpty || !attachments.isEmpty else { return }
        let previousDraft = draft
        clearDraft(for: chatID)
        clearPendingAttachments(for: chatID)

        let didQueue = chatStore.sendMessage(text: text, attachments: attachments, to: chatID)
        if !didQueue {
            if (draftsByChatID[chatID] ?? "").isEmpty {
                draftsByChatID[chatID] = previousDraft
            }
            if (pendingAttachmentsByChatID[chatID] ?? []).isEmpty {
                pendingAttachmentsByChatID[chatID] = attachments
            }
        }
    }

    private func saveEdit() {
        let text = trimmedDraft
        let editingChatID = chatStore.editingMessage?.chatID
        let previousDraft = draft
        if let editingChatID {
            clearDraft(for: editingChatID)
        }

        Task {
            let didSave = await chatStore.saveEdit(newText: text)
            if didSave {
                if let editingChatID {
                    clearDraft(for: editingChatID)
                }
            } else if
                let editingChatID,
                (draftsByChatID[editingChatID] ?? "").isEmpty
            {
                draftsByChatID[editingChatID] = previousDraft
            }
        }
    }

    // MARK: - Attachments

    func removePendingAttachment(id: PendingAttachment.ID) {
        guard let selectedChatID else { return }
        pendingAttachmentsByChatID[selectedChatID]?.removeAll { $0.id == id }
    }

    func addAttachment(data: Data, fileName: String, mimeType: String, to chatID: String) {
        pendingAttachmentsByChatID[chatID, default: []].append(PendingAttachment(
            fileData: data,
            fileName: fileName,
            mimeType: mimeType
        ))
    }

    private func clearPendingAttachments(for chatID: String) {
        pendingAttachmentsByChatID[chatID] = nil
    }

    func handleFileImport(_ result: Result<URL, Error>, for chatID: String) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else { return }
        addAttachment(data: data, fileName: url.lastPathComponent, mimeType: url.mimeType, to: chatID)
    }

    func handlePhotoPick(_ item: PhotosPickerItem, for chatID: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        let mimeType: String
        let fileName: String

        if let contentType = item.supportedContentTypes.first {
            mimeType = contentType.preferredMIMEType ?? "application/octet-stream"
            let ext = contentType.preferredFilenameExtension ?? "bin"
            fileName = "photo.\(ext)"
        } else {
            mimeType = "image/jpeg"
            fileName = "photo.jpg"
        }

        addAttachment(data: data, fileName: fileName, mimeType: mimeType, to: chatID)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty, let targetChatID = selectedChatID else { return false }

        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                guard let url else { return }
                guard let data = try? Data(contentsOf: url) else { return }
                let fileName = url.lastPathComponent
                let mimeType = url.mimeType

                Task { @MainActor in
                    self.addAttachment(data: data, fileName: fileName, mimeType: mimeType, to: targetChatID)
                }
            }
        }

        return true
    }
}
