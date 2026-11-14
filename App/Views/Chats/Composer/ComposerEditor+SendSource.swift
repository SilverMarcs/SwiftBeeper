#if os(iOS)
import UIKit

extension ComposerEditor {
    /// Where the bubble's text lines up with the draft, and the draft's
    /// visible characters, where the bubble's glyphs start from.
    /// - Parameter frame: The editor's frame in SwiftUI's global space.
    func sendText(in frame: CGRect) -> (anchor: CGPoint, anchorsLastLine: Bool, glyphs: [MessageSendSourceGlyph]) {
        layoutIfNeeded()
        let x = frame.minX + textContainerInset.left - bounds.minX
        let glyphs = visibleGlyphs(offsetBy: frame.origin)
        // A draft scrolled down lines up by its last line, which is in view.
        if isGrowing, bounds.minY > 0 {
            let end = caretRect(for: endOfDocument)
            return (CGPoint(x: x, y: frame.minY + end.maxY - bounds.minY), true, glyphs)
        }
        return (CGPoint(x: x, y: frame.minY + textContainerInset.top - bounds.minY), false, glyphs)
    }

    /// Each character in view, from the top of the scrolled window to its
    /// bottom; at rest, the first line up to its ellipsis.
    private func visibleGlyphs(offsetBy origin: CGPoint) -> [MessageSendSourceGlyph] {
        let string = text as NSString
        guard string.length > 0 else { return [] }

        var end = string.length
        var maximumX = CGFloat.infinity
        if !isGrowing {
            // At rest only the first line shows, truncated with an ellipsis
            // that takes the place of the characters it would overlap.
            let newline = string.rangeOfCharacter(from: .newlines)
            if newline.location != NSNotFound { end = newline.location }
            let font = font ?? .preferredFont(forTextStyle: .body)
            let available = bounds.width - textContainerInset.left - textContainerInset.right
            let width = string.substring(to: end).size(withAttributes: [.font: font]).width
            if width > available {
                let ellipsis = "…".size(withAttributes: [.font: font]).width
                maximumX = bounds.minX + textContainerInset.left + available - ellipsis
            }
        }

        // A draft scrolled past its top starts at the first line in view.
        var location = 0
        if isGrowing, bounds.minY > 0,
           let position = closestPosition(to: CGPoint(x: bounds.minX, y: bounds.minY)) {
            location = min(max(offset(from: beginningOfDocument, to: position), 0), string.length - 1)
            location = string.rangeOfComposedCharacterSequence(at: location).location
        }

        let leadingWhitespace = text.prefix { $0.isWhitespace }.utf16.count
        var glyphs: [MessageSendSourceGlyph] = []
        while location < end, glyphs.count < MessageSendSource.maximumGlyphs {
            let range = string.rangeOfComposedCharacterSequence(at: location)
            location = NSMaxRange(range)
            let character = string.substring(with: range)
            guard !character.allSatisfy(\.isWhitespace),
                  let start = position(from: beginningOfDocument, offset: range.location),
                  let finish = position(from: start, offset: range.length),
                  let characterRange = textRange(from: start, to: finish) else { continue }
            let rect = firstRect(for: characterRange)
            guard !rect.isNull, !rect.isInfinite else { continue }
            // Lines run downwards, so the first below the window ends it.
            if rect.minY >= bounds.maxY { break }
            guard rect.maxY > bounds.minY, rect.maxX <= maximumX + 0.5 else { continue }
            glyphs.append(MessageSendSourceGlyph(
                offset: range.location - leadingWhitespace,
                frame: rect.offsetBy(dx: origin.x - bounds.minX, dy: origin.y - bounds.minY)
            ))
        }
        return glyphs
    }
}
#endif
