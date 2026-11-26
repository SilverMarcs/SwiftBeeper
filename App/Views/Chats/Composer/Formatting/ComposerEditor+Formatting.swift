#if os(iOS)
import UIKit

extension ComposerEditor {
    /// The formats the edit menu offers for selected text. Multi-line code
    /// becomes a code block anyway.
    static let menuFormats: [ComposerFormat] = [.bold, .italic, .strikethrough, .code, .link, .quote, .bulletedList, .numberedList]

    /// The edit menu's Format submenu, which writes Markdown around the
    /// selection as the Mac's Format menu does.
    var formatMenu: UIMenu {
        UIMenu(
            title: "Format",
            image: UIImage(systemName: "textformat"),
            children: Self.menuFormats.map { format in
                UIAction(title: format.title, image: UIImage(systemName: format.systemImage)) { [weak self] _ in
                    self?.apply(format)
                }
            }
        )
    }

    func apply(_ format: ComposerFormat) {
        guard markedTextRange == nil, let edit = ComposerMarkdownEdit.applying(format, to: text, selection: selectedRange) else { return }
        perform(edit)
    }

    /// Makes `edit`'s replacements as one undoable change, as typing them
    /// would, so the draft and its mentions follow.
    func perform(_ edit: ComposerMarkdownEdit) {
        undoManager?.beginUndoGrouping()
        for replacement in edit.replacements {
            guard let start = position(from: beginningOfDocument, offset: replacement.range.location),
                  let end = position(from: start, offset: replacement.range.length),
                  let range = textRange(from: start, to: end) else { continue }
            replace(range, withText: replacement.text)
        }
        undoManager?.endUndoGrouping()
        let length = (text as NSString).length
        selectedRange = NSMaxRange(edit.selection) <= length ? edit.selection : NSRange(location: min(edit.selection.location, length), length: 0)
        scrollRangeToVisible(selectedRange)
    }

    /// Pasting a URL over selected text links the text, and rich text
    /// pastes as Markdown, as on the Mac.
    override func paste(_ sender: Any?) {
        guard markedTextRange == nil else { return super.paste(sender) }
        let pasteboard = UIPasteboard.general
        if let pasted = pasteboard.string,
           let edit = ComposerMarkdownEdit.pastingLink(pasted, in: text, selection: selectedRange) {
            perform(edit)
            return
        }
        if let markdown = PastedMarkdown.markdown(from: pasteboard),
           let edit = ComposerMarkdownEdit.pasting(markdown, in: text, selection: selectedRange) {
            perform(edit)
            return
        }
        super.paste(sender)
    }
}
#endif
