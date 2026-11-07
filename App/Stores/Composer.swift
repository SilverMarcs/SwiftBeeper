import Foundation
import Observation

/// One conversation's composer: its draft, attachments, and reply or edit.
/// `InputManager` keeps one per chat and thread, so drafts survive switching
/// between them, and a thread's composer works beside the chat's.
@MainActor
@Observable
final class Composer {
    let target: ComposerTarget

    /// The draft, with the identities of its mentions.
    var draft = ComposerDraft()
    /// The draft's text, as the field edits it.
    var text: String {
        get { draft.text }
        set {
            guard newValue != draft.text else { return }
            draft.updateText(newValue)
            selection = nil
            dismissedMentionQuery = nil
        }
    }
    var pendingAttachments: [PendingAttachment] = []
    private(set) var replyingTo: Message?
    private(set) var editing: Message?
    var isSavingEdit = false
    /// Slack's "Also send to channel", for a thread reply.
    var alsoSendToChat = false

    var selection: NSRange?
    var dismissedMentionQuery: ComposerMentionQuery?
    var attachmentImportError: String?

    /// Mirrors the field's focus, which the timeline follows.
    var isFocused = false
    /// Set while the field should take focus, such as for Reply, until the
    /// field has. A field appearing later, like a thread's, still sees it.
    private(set) var focusRequestID: UUID?
    /// Changes when dictation lands in the draft.
    private(set) var dictationFocusRequestID: UUID?

    /// Where a sent bubble flies from, for the iPhone search field, which
    /// submits from UIKit. Read at submission, before clearing the draft can
    /// shrink the composer.
    @ObservationIgnored var sourceFrame: (() -> CGRect?)?
    /// The iPhone search field's coordinate reference.
    @ObservationIgnored var searchReferenceFrame = CGRect.zero

    init(target: ComposerTarget) {
        self.target = target
    }

    /// The message the composer replies to or edits.
    var activeMessage: Message? { editing ?? replyingTo }
    var isEditing: Bool { editing != nil }

    var prompt: String {
        // The iPhone composers tell their fields apart by prompt.
        if isEditing { return target.isThread ? "Edit thread reply" : "Edit message" }
        if replyingTo != nil { return "Reply message" }
        return target.isThread ? "Reply in thread" : "Message"
    }

    var hasContent: Bool {
        !draft.text.trimmed.isEmpty || !pendingAttachments.isEmpty
    }

    // MARK: - Reply and edit

    func reply(to message: Message) {
        editing = nil
        replyingTo = message
        requestFocus()
    }

    /// Edits `message` in place of the draft.
    func startEditing(_ message: Message) {
        replyingTo = nil
        editing = message
        draft = ComposerDraft(message: message)
        selection = nil
        requestFocus()
    }

    /// Leaves reply or edit. An edit's text leaves with it.
    func cancelAction() {
        if editing != nil { draft = ComposerDraft() }
        replyingTo = nil
        editing = nil
    }

    /// Ends the edit after its save, keeping anything typed since.
    func finishEditing(_ message: Message) {
        guard editing?.id == message.id else { return }
        editing = nil
    }

    func clearReply() {
        replyingTo = nil
    }

    // MARK: - Focus

    func requestFocus() {
        focusRequestID = UUID()
    }

    func didHandleFocusRequest() {
        focusRequestID = nil
    }

    func requestDictationFocus() {
        dictationFocusRequestID = UUID()
    }
}
