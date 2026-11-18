#if os(macOS)
import AppKit

/// Lays out the composer's draft as it will look once sent: markup marked
/// hidden takes no glyphs, so no space, list markers draw as bullets, and
/// quotes get a bar beside them. The text itself is untouched, so the draft
/// stays the Markdown that's sent.
final class ComposerLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// How far a quote's text sits from the bar's edge.
    static let quoteIndent: CGFloat = 12
    private static let quoteBarWidth: CGFloat = 3

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let count = glyphRange.length
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var newProperties = Array(UnsafeBufferPointer(start: properties, count: count))
        var changed = false
        for index in 0..<count {
            let character = characterIndexes[index]
            guard character < storage.length else { continue }
            if storage.attribute(.composerHiddenMarkup, at: character, effectiveRange: nil) != nil {
                // A control character with no advance, rather than a null
                // glyph, which the typesetter would hang off the line before.
                newProperties[index] = .controlCharacter
                changed = true
            } else if storage.attribute(.composerBullet, at: character, effectiveRange: nil) != nil,
                      let bullet = Self.bulletGlyph(in: font) {
                newGlyphs[index] = bullet
                changed = true
            }
        }
        guard changed else { return 0 }
        layoutManager.setGlyphs(newGlyphs, properties: newProperties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return count
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt characterIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = layoutManager.textStorage, characterIndex < storage.length,
              storage.attribute(.composerHiddenMarkup, at: characterIndex, effectiveRange: nil) != nil else { return action }
        return .zeroAdvancement
    }

    private static func bulletGlyph(in font: NSFont) -> CGGlyph? {
        var character: UniChar = 0x2022
        var glyph: CGGlyph = 0
        return CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1) ? glyph : nil
    }

    /// Draws a bar beside each quote line.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        NSColor.tertiaryLabelColor.setFill()
        storage.enumerateAttribute(.composerQuote, in: characters) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                let bar = NSRect(x: origin.x + rect.minX, y: origin.y + rect.minY, width: Self.quoteBarWidth, height: rect.height)
                NSBezierPath(roundedRect: bar, xRadius: Self.quoteBarWidth / 2, yRadius: Self.quoteBarWidth / 2).fill()
            }
        }
    }
}
#endif
