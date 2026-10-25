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
    #if os(iOS)
    let sendAnimator = MessageSendAnimator()
    #endif

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

    /// Mirrors the composer's `FocusState` (set by `MessageInputView` and
    /// `SearchFieldComposer`) so the timeline, which owns the scroll proxy, can
    /// scroll to the newest message, or the reply/edit target, when the
    /// keyboard comes up.
    var isComposerFocused = false

    #if os(iOS)
    /// How long the composers wait before focusing for Reply or Edit. Both come
    /// from a message's context menu, whose actions run while it is still
    /// dismissing. When dismissal finishes, UIKit restores the keyboard state
    /// from before the menu opened, which resigns a field focused any earlier.
    static let contextMenuDismissalDelay: Duration = .milliseconds(200)
    #endif

    init(chatStore: ChatStore) {
        self.chatStore = chatStore
        #if os(iOS)
        chatStore.onOutgoingMessageConfirmed = { [sendAnimator] outgoingID, message in
            sendAnimator.confirm(outgoingID, as: message)
        }
        #endif
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

    var trimmedDraft: String { draft.trimmed }

    /// Appends a reply that failed to send from a notification to that chat's
    /// draft, so it is ready to resend when the chat opens.
    func restoreNotificationDraft(_ text: String, for chatID: String) {
        let existing = draftsByChatID[chatID] ?? ""
        draftsByChatID[chatID] = existing.isEmpty ? text : existing + "\n" + text
        pendingFocus = true
    }

    // MARK: - Derived composer state

    var isEditing: Bool { chatStore.editingMessage != nil }

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

    /// The Edit Last shortcut. Scans the timeline, so keep it out of view bodies.
    func editMostRecentOutgoingMessage() {
        guard let chat = chatStore.selectedChat,
              let message = chatStore.timelineMessages.last(where: { chatStore.canEdit($0, in: chat) })
        else { return }
        startEditing(message, in: chat)
    }

    func cancelComposerAction() {
        withAnimation {
            let editingChatID = chatStore.editingMessage?.chatID
            chatStore.cancelComposerAction()
            if let editingChatID {
                draftsByChatID[editingChatID] = nil
                editingDraftChatID = nil
            }
        }
    }

    // MARK: - Submit

    func handleSubmit(sourceFrame: CGRect? = nil) {
        if isEditing {
            saveEdit()
        } else {
            sendMessage(from: sourceFrame)
        }
    }

    private func sendMessage(from sourceFrame: CGRect?) {
        guard let chatID = chatStore.selectedChatID else { return }
        let text = trimmedDraft
        let attachments = pendingAttachments

        guard !text.isEmpty || !attachments.isEmpty else { return }
        #if os(iOS)
        let animationSource = sourceFrame ?? sendAnimator.sourceFrame?()
        #endif
        draftsByChatID[chatID] = nil
        pendingAttachmentsByChatID[chatID] = nil

        #if os(iOS)
        if let outgoing = chatStore.sendMessage(text: text, attachments: attachments, to: chatID) {
            sendAnimator.begin(outgoing, from: animationSource)
        }
        #else
        chatStore.sendMessage(text: text, attachments: attachments, to: chatID)
        #endif
    }

    private func saveEdit() {
        let text = trimmedDraft
        let editingChatID = chatStore.editingMessage?.chatID
        let previousDraft = draft
        if let editingChatID {
            draftsByChatID[editingChatID] = nil
        }
        // The draft is already clear, so the edit ending must not clear
        // anything typed while the save runs.
        editingDraftChatID = nil

        Task {
            let didSave = await chatStore.saveEdit(newText: text)
            guard !didSave, let editingChatID else { return }
            // Still editing: restore the text unless something new was typed.
            editingDraftChatID = editingChatID
            if (draftsByChatID[editingChatID] ?? "").isEmpty {
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
