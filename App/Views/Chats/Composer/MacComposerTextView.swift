#if os(macOS)
import SwiftUI

/// The macOS composer's editor: an `NSTextView` that grows with the draft
/// up to `maximumLines` and scrolls past them, with the draft's mentions in
/// the accent color. It looks and behaves as the vertical `TextField` it
/// replaced: Return sends, and Shift- or Option-Return adds a line.
struct MacComposerTextView: NSViewRepresentable {
    @Binding var text: String
    /// Asks for focus, and follows it.
    @Binding var isFocused: Bool
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
    static let maximumLines = 7

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let editor = MacComposerEditor()
        editor.delegate = context.coordinator
        editor.string = text
        editor.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.focusDidChange(focused)
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = editor
        context.coordinator.editor = editor
        sendOrigin.editor = editor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let editor = coordinator.editor else { return }
        editor.placeholder = placeholder

        // Leave text being composed with marked text alone; replacing it
        // would end the composition.
        if editor.string != text, !editor.hasMarkedText() {
            editor.string = text
            if let selection, NSMaxRange(selection) <= (text as NSString).length {
                editor.setSelectedRange(selection)
            }
            editor.needsDisplay = true
        }
        if !editor.hasMarkedText(), coordinator.styledText != editor.string || coordinator.styledMentions != mentions {
            coordinator.styledText = editor.string
            coordinator.styledMentions = mentions
            if let storage = editor.textStorage {
                ComposerMentionStyle.apply(
                    to: storage,
                    mentions: mentions,
                    font: MacComposerEditor.font,
                    textColor: .textColor,
                    mentionColor: NSColor(Color.accentColor)
                )
            }
            editor.typingAttributes = ComposerMentionStyle.plainAttributes(font: MacComposerEditor.font, textColor: .textColor)
        }

        // Focus changes from outside AppKit land after this update, so they
        // don't run inside SwiftUI's view update.
        let isFirstResponder = editor.window?.firstResponder === editor
        if isFocused != isFirstResponder {
            Task { @MainActor [weak editor] in
                guard let editor, let window = editor.window,
                      isFocused != (window.firstResponder === editor) else { return }
                window.makeFirstResponder(isFocused ? editor : nil)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let height = MacComposerEditor.fittingHeight(of: text, width: width, maximumLines: Self.maximumLines)
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacComposerTextView
        weak var editor: MacComposerEditor?
        /// The text and mentions the editor was last styled for.
        var styledText: String?
        var styledMentions: [NSRange] = []

        init(parent: MacComposerTextView) {
            self.parent = parent
        }

        func focusDidChange(_ focused: Bool) {
            guard parent.isFocused != focused else { return }
            parent.isFocused = focused
        }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            if parent.text != editor.string {
                parent.text = editor.string
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor else { return }
            // The caret taking a mention's colour from the letter before it
            // would colour what's typed next.
            if !editor.hasMarkedText() {
                editor.typingAttributes = ComposerMentionStyle.plainAttributes(font: MacComposerEditor.font, textColor: .textColor)
            }
            let range = editor.selectedRange()
            let draft = editor.string
            // Wait for the text to land in the draft, then report only a
            // caret that still matches it.
            Task { @MainActor [weak self, weak editor] in
                await Task.yield()
                guard let self, let editor, editor.string == draft, editor.selectedRange() == range,
                      parent.text == draft else { return }
                parent.onSelectionChange(range)
            }
        }

        /// Return sends; Shift- or Option-Return starts a new line. A
        /// composition, such as Japanese input, keeps its own Return.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() else { return false }
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            if modifiers.contains(.shift) || modifiers.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onReturn()
            }
            return true
        }
    }
}
#endif
