#if os(macOS)
import AppKit

extension NSAttributedString.Key {
    /// Markup that isn't drawn: `ComposerLayoutManager` gives it no glyphs.
    static let composerHiddenMarkup = NSAttributedString.Key("RelayComposerHiddenMarkup")
    /// A list item's `-`, `*` or `+`, drawn as a bullet.
    static let composerBullet = NSAttributedString.Key("RelayComposerBullet")
    /// A quote's line, drawn with a bar beside it.
    static let composerQuote = NSAttributedString.Key("RelayComposerQuote")
}

extension NSAttributedString {
    /// The text as the composer draws it, with hidden markup removed and
    /// bullets in place of list markers, for drawing it elsewhere.
    var composerDisplayed: NSAttributedString {
        let result = NSMutableAttributedString(attributedString: self)
        let whole = NSRange(location: 0, length: result.length)
        var bullets: [NSRange] = []
        result.enumerateAttribute(.composerBullet, in: whole) { value, range, _ in
            if value != nil { bullets.append(range) }
        }
        for range in bullets {
            result.replaceCharacters(in: range, with: String(repeating: "•", count: range.length))
        }
        var hidden: [NSRange] = []
        result.enumerateAttribute(.composerHiddenMarkup, in: whole) { value, range, _ in
            if value != nil { hidden.append(range) }
        }
        for range in hidden.reversed() {
            result.deleteCharacters(in: range)
        }
        return result
    }
}
#endif
