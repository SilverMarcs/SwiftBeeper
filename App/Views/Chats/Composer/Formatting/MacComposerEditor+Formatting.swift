#if os(macOS)
import AppKit

extension MacComposerEditor {
    /// The composer editor that has focus in the key window, which the
    /// Format menu's commands act on.
    static var focused: MacComposerEditor? {
        NSApp.keyWindow?.firstResponder as? MacComposerEditor
    }

    /// Formats the selection, as the Format menu's commands and their
    /// shortcuts do.
    func apply(_ format: ComposerFormat) {
        guard !hasMarkedText(), let edit = ComposerMarkdownEdit.applying(format, to: string, selection: selectedRange()) else { return }
        perform(edit)
    }

    /// Makes `edit`'s replacements as one undoable change, telling the
    /// delegate about each, so the draft follows its mentions through them.
    func perform(_ edit: ComposerMarkdownEdit) {
        guard let textStorage else { return }
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        for replacement in edit.replacements {
            guard shouldChangeText(in: replacement.range, replacementString: replacement.text) else { continue }
            textStorage.replaceCharacters(in: replacement.range, with: replacement.text)
            didChangeText()
        }
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
        let length = (string as NSString).length
        let selection = NSRange(location: min(edit.selection.location, length), length: 0)
        setSelectedRange(NSMaxRange(edit.selection) <= length ? edit.selection : selection)
        scrollRangeToVisible(selectedRange())
    }

    /// The Format menu's shortcuts, taken here first so they work while the
    /// editor has focus whatever the keyboard layout does with Shift.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, let format = ComposerFormat(event: event) {
            apply(format)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Pasting a URL over selected text links the text, as in Slack. Rich
    /// text pastes as Markdown, keeping its formatting; Paste and Match
    /// Style still pastes it plain.
    override func paste(_ sender: Any?) {
        guard !hasMarkedText() else { return super.paste(sender) }
        let pasteboard = NSPasteboard.general
        if let pasted = pasteboard.string(forType: .string),
           let edit = ComposerMarkdownEdit.pastingLink(pasted, in: string, selection: selectedRange()) {
            perform(edit)
            return
        }
        if let markdown = PastedMarkdown.markdown(from: pasteboard),
           let edit = ComposerMarkdownEdit.pasting(markdown, in: string, selection: selectedRange()) {
            perform(edit)
            return
        }
        super.paste(sender)
    }
}
#endif
