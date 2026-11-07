import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Drives every composer: one `Composer` per chat and thread, holding its
/// draft, attachments, and reply or edit, plus what they share: dictation,
/// mention suggestions, and the send animation. It sits on top of
/// `ChatStore`, which owns sending, edits, and the outbox, so the inline
/// composer (`MessageInputView`) and the iPhone `.searchable` composer drive
/// the same state.
@MainActor
@Observable
final class InputManager {
    let dictation = ComposerDictation()
    private(set) var isSubmittingDictation = false
    /// The composer the running dictation writes into.
    private(set) var dictationTarget: ComposerTarget?
    let chatStore: ChatStore
    let sendAnimator = MessageSendAnimator()

    var mentionParticipants: [ChatParticipant] = []
    var mentionParticipantsChatID: String?

    /// Created on first use. Composers are observable themselves, so adding
    /// one from a view body doesn't invalidate anything.
    @ObservationIgnored private var composers: [ComposerTarget: Composer] = [:]

    #if os(iOS)
    /// How long the composers wait before focusing for Reply or Edit. Both come
    /// from a message's context menu, whose actions run while it is still
    /// dismissing. When dismissal finishes, UIKit restores the keyboard state
    /// from before the menu opened, which resigns a field focused any earlier.
    static let contextMenuDismissalDelay: Duration = .milliseconds(200)
    #endif

    init(chatStore: ChatStore) {
        self.chatStore = chatStore
        chatStore.onOutgoingMessageConfirmed = { [sendAnimator] outgoingID, message in
            sendAnimator.confirm(outgoingID, as: message)
        }
        // Leaving a chat ends its replies and edits, so none waits, dimming
        // the timeline, for its return.
        chatStore.onChatClosed = { [weak self] chatID in
            guard let self else { return }
            for composer in composers.values where composer.target.chatID == chatID {
                composer.cancelAction()
            }
        }
        chatStore.onThreadClosed = { [weak self] target in
            guard let composer = self?.composers[target] else { return }
            composer.cancelAction()
            composer.isFocused = false
        }
    }

    func composer(for target: ComposerTarget) -> Composer {
        if let composer = composers[target] { return composer }
        let composer = Composer(target: target)
        composers[target] = composer
        return composer
    }

    /// Whether any composer has the keyboard. Paste goes to the focused one,
    /// or to the chat's when none is.
    var isAnyComposerFocused: Bool {
        composers.values.contains(where: \.isFocused)
    }

    /// Appends a reply that failed to send from a notification to that chat's
    /// draft, so it is ready to resend when the chat opens.
    func restoreNotificationDraft(_ text: String, for chatID: String) {
        let composer = composer(for: ComposerTarget(chatID: chatID))
        composer.text = composer.text.isEmpty ? text : composer.text + "\n" + text
        composer.requestFocus()
    }

    // MARK: - Dictation

    func toggleDictation(in composer: Composer, using settings: DictationSettings) {
        guard !isSubmittingDictation, settings.isEnabled else { return }
        // One dictation at a time, finished by the composer that started it.
        if dictation.isActive {
            guard dictationTarget == composer.target else { return }
        } else {
            dictationTarget = composer.target
        }
        let editingID = composer.editing?.id
        dictation.toggle(provider: OpenAITranscriber(apiKey: settings.apiKey)) { [weak composer] text in
            guard let composer, composer.editing?.id == editingID else { return }
            let draft = composer.text
            composer.text = draft + (draft.isEmpty || draft.last?.isWhitespace == true ? "" : " ") + text
            composer.requestDictationFocus()
        }
    }

    /// Cancels dictation when it belongs to `composer`.
    func cancelDictation(for composer: Composer) {
        guard dictationTarget == composer.target else { return }
        dictation.cancel()
    }

    func isDictating(in composer: Composer) -> Bool {
        dictationTarget == composer.target && dictation.isActive
    }

    func canSubmit(_ composer: Composer) -> Bool {
        if isSubmittingDictation || composer.isSavingEdit { return false }
        return composer.hasContent || isDictating(in: composer)
    }

    // MARK: - Reply and edit

    func startEditing(_ message: Message, in composer: Composer) {
        guard let chat = chatStore.chat(byID: message.chatID), chatStore.canEdit(message, in: chat) else { return }
        withAnimation {
            composer.startEditing(message)
        }
    }

    /// The Edit Last shortcut. Scans the timeline, so keep it out of view bodies.
    func editMostRecentOutgoingMessage(in composer: Composer) {
        guard let chat = chatStore.selectedChat,
              let message = chatStore.timelineMessages.last(where: { chatStore.canEdit($0, in: chat) })
        else { return }
        startEditing(message, in: composer)
    }

    /// Replies in `message`'s thread on networks that reply in threads, or
    /// quotes it.
    func reply(to message: Message, in composer: Composer) {
        if !composer.target.isThread, let chat = chatStore.chat(byID: message.chatID), chatStore.repliesInThreads(in: chat) {
            chatStore.showThread(for: message)
            let rootID = message.threadRootID ?? message.id
            self.composer(for: ComposerTarget(chatID: message.chatID, threadRootID: rootID)).requestFocus()
        } else {
            withAnimation {
                composer.reply(to: message)
            }
        }
    }

    func cancelAction(in composer: Composer) {
        withAnimation {
            composer.cancelAction()
        }
    }

    // MARK: - Submit

    func submit(_ composer: Composer, sourceFrame: CGRect? = nil) {
        guard !isSubmittingDictation else { return }
        if isDictating(in: composer) {
            let session = dictation.sessionID
            let composerMessageID = composer.activeMessage?.id
            isSubmittingDictation = true
            Task {
                defer { isSubmittingDictation = false }
                guard await dictation.finish(session: session),
                      composer.activeMessage?.id == composerMessageID else { return }
                submitDraft(of: composer, sourceFrame: sourceFrame)
            }
            return
        }
        submitDraft(of: composer, sourceFrame: sourceFrame)
    }

    private func submitDraft(of composer: Composer, sourceFrame: CGRect?) {
        if let message = composer.editing {
            saveEdit(of: message, in: composer)
        } else {
            send(composer, from: sourceFrame)
        }
    }

    private func send(_ composer: Composer, from sourceFrame: CGRect?) {
        let snapshot = composer.draft.trimmed
        let attachments = composer.pendingAttachments
        guard !snapshot.text.isEmpty || !attachments.isEmpty else { return }
        let animationSource = sourceFrame ?? composer.sourceFrame?()
        let outgoing = chatStore.sendMessage(
            text: snapshot.text,
            mentions: snapshot.mentions,
            attachments: attachments,
            to: composer.target,
            replyingTo: composer.replyingTo?.id,
            alsoSendToChat: composer.alsoSendToChat
        )
        composer.draft = ComposerDraft()
        composer.pendingAttachments = []
        composer.alsoSendToChat = false
        composer.clearReply()
        if let outgoing {
            sendAnimator.begin(outgoing, from: animationSource)
        }
    }

    /// Clears the draft while the save runs; a failed save restores it unless
    /// something new was typed, and keeps the edit open.
    private func saveEdit(of message: Message, in composer: Composer) {
        let previousDraft = composer.draft
        let snapshot = previousDraft.trimmed
        guard !snapshot.text.isEmpty else { return }
        composer.draft = ComposerDraft()
        composer.isSavingEdit = true
        Task {
            defer { composer.isSavingEdit = false }
            do {
                try await APIClient.editMessage(
                    chatID: message.chatID, messageID: message.id, text: snapshot.text, mentions: snapshot.mentions
                )
                composer.finishEditing(message)
                chatStore.clearMessageError(in: composer.target)
            } catch {
                chatStore.handleMessageError(error, in: composer.target)
                if composer.text.isEmpty { composer.draft = previousDraft }
            }
        }
    }

    // MARK: - Attachments

    func addAttachment(data: Data, fileName: String, mimeType: String, to composer: Composer) {
        composer.pendingAttachments.append(PendingAttachment(fileData: data, fileName: fileName, mimeType: mimeType))
    }

    func handleFileImport(_ result: Result<URL, Error>, for composer: Composer) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else { return }
        addAttachment(data: data, fileName: url.lastPathComponent, mimeType: url.mimeType, to: composer)
    }

    func handlePhotoPick(_ item: PhotosPickerItem, for composer: Composer) async {
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

        addAttachment(data: data, fileName: fileName, mimeType: mimeType, to: composer)
    }

    func handleDrop(_ providers: [NSItemProvider], into composer: Composer) -> Bool {
        guard !providers.isEmpty else { return false }

        let transfers = providers.map { DroppedAttachment.beginLoading(from: $0) }
        Task {
            for transfer in transfers {
                do {
                    for try await attachment in transfer {
                        composer.pendingAttachments.append(attachment)
                    }
                } catch {
                    composer.attachmentImportError = error.localizedDescription
                }
            }
        }

        return true
    }
}
