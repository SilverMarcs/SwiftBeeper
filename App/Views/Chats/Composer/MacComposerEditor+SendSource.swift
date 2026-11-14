#if os(macOS)
import AppKit

extension MacComposerEditor {
    /// Where the bubble's text lines up with the draft, and the draft's
    /// visible characters. The editor is flipped and fills its
    /// scroll view, so the visible window's top-left is the SwiftUI frame's.
    /// - Parameter frame: The editor's scroll view frame in SwiftUI's
    ///   global space.
    func sendText(in frame: CGRect) -> (anchor: CGPoint, anchorsLastLine: Bool, glyphs: [MessageSendSourceGlyph]) {
        let visible = visibleRect
        let container = textContainerOrigin
        let x = frame.minX + container.x - visible.minX
        let glyphs = visibleGlyphs(in: visible, offsetBy: frame.origin)
        // A draft scrolled down lines up by its last line, which is in view.
        if visible.minY > 0, let layoutManager, let textContainer {
            let bottom = layoutManager.usedRect(for: textContainer).maxY + container.y
            return (CGPoint(x: x, y: frame.minY + bottom - visible.minY), true, glyphs)
        }
        return (CGPoint(x: x, y: frame.minY + container.y - visible.minY), false, glyphs)
    }

    /// Each character in the scroll view's visible window.
    private func visibleGlyphs(in visible: CGRect, offsetBy origin: CGPoint) -> [MessageSendSourceGlyph] {
        guard let layoutManager, let textContainer, !string.isEmpty else { return [] }
        let text = string as NSString
        let container = textContainerOrigin
        let containerVisible = visible.offsetBy(dx: -container.x, dy: -container.y)
        layoutManager.ensureLayout(forBoundingRect: containerVisible, in: textContainer)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerVisible, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let leadingWhitespace = string.prefix { $0.isWhitespace }.utf16.count
        var glyphs: [MessageSendSourceGlyph] = []
        var location = characters.location
        while location < NSMaxRange(characters), location < text.length, glyphs.count < MessageSendSource.maximumGlyphs {
            let range = text.rangeOfComposedCharacterSequence(at: location)
            location = NSMaxRange(range)
            let character = text.substring(with: range)
            guard !character.allSatisfy(\.isWhitespace) else { continue }
            let characterGlyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard characterGlyphs.length > 0 else { continue }
            let rect = layoutManager.boundingRect(forGlyphRange: characterGlyphs, in: textContainer)
                .offsetBy(dx: container.x, dy: container.y)
            guard rect.intersects(visible) else { continue }
            glyphs.append(MessageSendSourceGlyph(
                offset: range.location - leadingWhitespace,
                frame: rect.offsetBy(dx: origin.x - visible.minX, dy: origin.y - visible.minY)
            ))
        }
        return glyphs
    }
}
#endif
