#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Colours a draft's mentions in a composer's editor, so the user sees which
/// names will be sent as mentions and when an edit has broken one. Only the
/// styling changes; the text, and so the caret and undo, are left alone.
enum ComposerMentionStyle {
    #if os(iOS)
    typealias Font = UIFont
    typealias Color = UIColor
    #else
    typealias Font = NSFont
    typealias Color = NSColor
    #endif

    /// The editor's plain text attributes, which typing always uses, so a
    /// letter typed right after a mention doesn't take on its colour.
    static func plainAttributes(font: Font, textColor: Color) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: textColor]
    }

    /// Restyles `storage`: plain text, with each mention range in
    /// `mentionColor`. Ranges outside the text are skipped.
    static func apply(
        to storage: NSTextStorage,
        mentions: [NSRange],
        font: Font,
        textColor: Color,
        mentionColor: Color
    ) {
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(plainAttributes(font: font, textColor: textColor), range: whole)
        for mention in mentions where mention.length > 0 && NSMaxRange(mention) <= storage.length {
            storage.addAttribute(.foregroundColor, value: mentionColor, range: mention)
        }
        storage.endEditing()
    }
}
