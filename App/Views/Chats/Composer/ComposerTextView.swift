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
    /// Where the caret goes when the draft is replaced from outside, as when
    /// a mention is inserted.
    let selection: NSRange?
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
            editor.textDidChange()
        }
        // Focus changes from outside UIKit land after this update, so they
        // don't run inside SwiftUI's view update.
        if isFocused != editor.isFirstResponder {
            Task { @MainActor [weak editor] in
                guard let editor, editor.window != nil, isFocused != editor.isFirstResponder else { return }
                if isFocused { editor.focus() } else { _ = editor.resignFirstResponder() }
            }
        }
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
