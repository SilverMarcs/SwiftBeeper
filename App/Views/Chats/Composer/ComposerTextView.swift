#if os(iOS)
import SwiftUI

/// The composer bar's editor: a `UITextView` that shows the draft's first
/// line at rest and grows with the draft while it's being written.
///
/// The keyboard's Return adds a line. A hardware keyboard's Return sends,
/// and Shift- or Option-Return adds a line.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    /// Asks for focus, and follows it.
    @Binding var isFocused: Bool
    /// Whether the editor is first responder: set only once UIKit has moved
    /// focus, after the keyboard's own announcements.
    @Binding var isEditing: Bool
    /// Changes each time the composer asks for focus, which the editor then
    /// takes even if `isFocused` was already true.
    let focusAttempt: Int
    /// Told about the editor, so a send can read where the draft is drawn.
    let sendOrigin: ComposerSendOrigin
    /// Where the caret goes when the draft is replaced from outside, as when
    /// a mention is inserted.
    let selection: NSRange?
    /// The draft's mentions, coloured in the text.
    let mentions: [NSRange]
    let placeholder: String
    let onSelectionChange: (NSRange) -> Void
    let onReturn: () -> Void

    /// The tallest the editor grows before it scrolls.
    static let maximumLines = 6

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, isEditing: $isEditing, onSelectionChange: onSelectionChange)
    }

    func makeUIView(context: Context) -> ComposerEditor {
        let editor = ComposerEditor()
        editor.delegate = context.coordinator
        editor.text = text
        editor.textDidChange()
        sendOrigin.editor = editor
        return editor
    }

    func updateUIView(_ editor: ComposerEditor, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused
        context.coordinator.isEditing = $isEditing
        context.coordinator.onSelectionChange = onSelectionChange
        editor.onReturn = onReturn
        editor.placeholder = placeholder
        editor.isGrowing = isEditing
        // Leave text being composed with marked text alone; replacing it
        // would end the composition.
        if editor.text != text, editor.markedTextRange == nil {
            editor.text = text
            if let selection, selection.upperBound <= (text as NSString).length {
                editor.selectedRange = selection
            }
            // A draft emptied by sending snaps back to one line under the
            // bubble leaving it, while the timeline scrolls to the sent
            // message; holding the timeline to the field would jump it there.
            editor.textDidChange(announcesResize: !text.isEmpty)
        }
        // Restyled whenever the text or its mentions change, once any
        // composition has ended.
        if editor.markedTextRange == nil,
           context.coordinator.styledText != editor.text || context.coordinator.styledMentions != mentions {
            context.coordinator.styledText = editor.text
            context.coordinator.styledMentions = mentions
            Self.styleMentions(mentions, in: editor)
        }
        // Focus changes from outside UIKit land after this update, so they
        // don't run inside SwiftUI's view update.
        if !isFocused { editor.cancelPendingFocus() }
        if context.coordinator.focusAttempt != focusAttempt {
            context.coordinator.focusAttempt = focusAttempt
            Task { @MainActor [weak editor] in
                guard let editor, isFocused else { return }
                editor.focus()
            }
        } else if isFocused != editor.isFirstResponder {
            Task { @MainActor [weak editor] in
                guard let editor, editor.window != nil, isFocused != editor.isFirstResponder else { return }
                if isFocused { editor.focus() } else { _ = editor.resignFirstResponder() }
            }
        }
    }

    private static func styleMentions(_ mentions: [NSRange], in editor: ComposerEditor) {
        let font = editor.font ?? .preferredFont(forTextStyle: .body)
        ComposerMentionStyle.apply(
            to: editor.textStorage,
            mentions: mentions,
            font: font,
            textColor: .label,
            mentionColor: editor.tintColor
        )
        editor.typingAttributes = ComposerMentionStyle.plainAttributes(font: font, textColor: .label)
    }

    /// Exactly the room `ComposerBarLayout` gives it, rather than the
    /// draft's unwrapped width UIKit would ask for.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView editor: ComposerEditor, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        var isEditing: Binding<Bool>
        var onSelectionChange: (NSRange) -> Void
        /// The focus attempt the editor last acted on.
        var focusAttempt = 0
        /// The text and mentions the editor was last styled for.
        var styledText: String?
        var styledMentions: [NSRange] = []

        init(text: Binding<String>, isFocused: Binding<Bool>, isEditing: Binding<Bool>, onSelectionChange: @escaping (NSRange) -> Void) {
            self.text = text
            self.isFocused = isFocused
            self.isEditing = isEditing
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChange(_ textView: UITextView) {
            (textView as? ComposerEditor)?.textDidChange()
            if text.wrappedValue != textView.text {
                text.wrappedValue = textView.text
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // The caret taking a mention's colour from the letter before it
            // would colour what's typed next.
            if textView.markedTextRange == nil, let font = textView.font {
                textView.typingAttributes = ComposerMentionStyle.plainAttributes(font: font, textColor: .label)
            }
            let range = textView.selectedRange
            let draft = textView.text
            // Typing reports the new caret before the new text. Wait for the
            // text to land, then report only a caret that still matches it.
            Task { @MainActor [weak textView] in
                await Task.yield()
                guard let textView, textView.text == draft, textView.selectedRange == range,
                      text.wrappedValue == draft else { return }
                onSelectionChange(range)
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing.wrappedValue = true
            if !isFocused.wrappedValue { isFocused.wrappedValue = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing.wrappedValue = false
            if isFocused.wrappedValue { isFocused.wrappedValue = false }
        }
    }
}
#endif
