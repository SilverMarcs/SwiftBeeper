#if os(macOS)
import AppKit

/// Styles a macOS draft as it will read once sent: bold, italic, code and
/// the rest take effect as they're typed, and the markup that won't show is
/// hidden, unless the selection is on it, where it shows dimmed so it can
/// be edited. Only attributes change, so the text, caret and undo are left
/// alone, and every style keeps the body font's size, so lines keep their
/// height. `ComposerLayoutManager` draws the hiding, bullets and quote bars.
enum ComposerMarkdownStyle {
    /// Restyles all of `storage`: plain text, its Markdown, then the draft's
    /// mentions in `mentionColor`. Returns the Markdown's spans, for
    /// `updateHiddenMarkup` as the selection moves.
    @discardableResult
    static func apply(
        to storage: NSTextStorage,
        mentions: [NSRange],
        selection: NSRange?,
        font: NSFont,
        textColor: NSColor,
        mentionColor: NSColor
    ) -> [ComposerMarkdownSpan] {
        let whole = NSRange(location: 0, length: storage.length)
        let spans = ComposerMarkdownParser.spans(in: storage.string, opaque: mentions)
        storage.beginEditing()
        storage.setAttributes(ComposerMentionStyle.plainAttributes(font: font, textColor: textColor), range: whole)

        // Fonts first, so traits land on code's monospaced font too.
        let monospaced = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        for span in spans where span.kind == .code || span.kind == .codeBlock {
            storage.addAttribute(.font, value: monospaced, range: span.range)
            if span.kind == .code {
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: span.range)
            }
        }
        for span in spans {
            switch span.kind {
            case .bold, .heading: addTrait(.bold, to: storage, in: span.range)
            case .italic: addTrait(.italic, to: storage, in: span.range)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
            default: break
            }
        }

        // Markup's dimming wins over the colour of what it's inside.
        for span in spans {
            switch span.kind {
            case .link: storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: span.range)
            case .quote, .listMarker: storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
            default: break
            }
        }
        for span in spans where span.kind == .syntax {
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: span.range)
        }
        for mention in mentions where mention.length > 0 && NSMaxRange(mention) <= storage.length {
            storage.addAttribute(.foregroundColor, value: mentionColor, range: mention)
        }

        let text = storage.string as NSString
        for span in spans {
            switch span.kind {
            case .listMarker where span.range.length == 1 && "-*+".contains(text.substring(with: span.range)):
                storage.addAttribute(.composerBullet, value: true, range: span.range)
            case .quoteLine:
                storage.addAttribute(.composerQuote, value: true, range: span.range)
                storage.addAttribute(.paragraphStyle, value: quoteParagraphStyle, range: span.range)
            default: break
            }
        }
        hideMarkup(in: storage, spans: spans, selection: selection)
        storage.endEditing()
        return spans
    }

    /// Hides `spans`' markup again for a new selection, showing only what
    /// it touches.
    static func updateHiddenMarkup(in storage: NSTextStorage, spans: [ComposerMarkdownSpan], selection: NSRange?) {
        storage.beginEditing()
        storage.removeAttribute(.composerHiddenMarkup, range: NSRange(location: 0, length: storage.length))
        hideMarkup(in: storage, spans: spans, selection: selection)
        storage.endEditing()
    }

    private static func hideMarkup(in storage: NSTextStorage, spans: [ComposerMarkdownSpan], selection: NSRange?) {
        for span in spans where span.kind == .syntax && NSMaxRange(span.range) <= storage.length {
            guard let reveal = span.reveal, !touches(selection, reveal) else { continue }
            storage.addAttribute(.composerHiddenMarkup, value: true, range: span.range)
        }
    }

    /// Whether the selection is in `range` or right at either end of it.
    private static func touches(_ selection: NSRange?, _ range: NSRange) -> Bool {
        guard let selection else { return false }
        if selection.length == 0 {
            return selection.location >= range.location && selection.location <= NSMaxRange(range)
        }
        return selection.location <= NSMaxRange(range) && NSMaxRange(selection) >= range.location
    }

    private static let quoteParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = ComposerLayoutManager.quoteIndent
        style.headIndent = ComposerLayoutManager.quoteIndent
        return style
    }()

    /// Markup's colour: tertiary in light mode, but secondary in dark mode,
    /// where tertiary is too faint to read.
    private static let syntaxColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .secondaryLabelColor : .tertiaryLabelColor
    }

    private static func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
            if let styled = NSFont(descriptor: descriptor, size: font.pointSize) {
                storage.addAttribute(.font, value: styled, range: subrange)
            }
        }
    }
}
#endif
