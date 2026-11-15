#if os(iOS)
import UIKit

extension ComposerEditor {
    /// Where the bubble's text lines up with the draft, and the draft's
    /// visible lines drawn for the flight.
    /// - Parameter frame: The editor's frame in SwiftUI's global space.
    func sendText(in frame: CGRect) -> (anchor: CGPoint, anchorsLastLine: Bool, picture: MessageSendPicture?) {
        layoutIfNeeded()
        let x = frame.minX + textContainerInset.left - bounds.minX
        let picture = visibleText(in: frame)
        // A draft scrolled down lines up by its last line, which is in view.
        if isGrowing, bounds.minY > 0 {
            let end = caretRect(for: endOfDocument)
            return (CGPoint(x: x, y: frame.minY + end.maxY - bounds.minY), true, picture)
        }
        return (CGPoint(x: x, y: frame.minY + textContainerInset.top - bounds.minY), false, picture)
    }

    /// The draft as the editor shows it, in the bubble's white: wrapped and
    /// scrolled while growing, or its first line cut off with an ellipsis at
    /// rest.
    private func visibleText(in frame: CGRect) -> MessageSendPicture? {
        guard hasText, bounds.width > 0, bounds.height > 0 else { return nil }
        let text = NSMutableAttributedString(attributedString: attributedText)
        let whole = NSRange(location: 0, length: text.length)
        text.addAttribute(.foregroundColor, value: UIColor.white, range: whole)
        let insets = textContainerInset
        let width = bounds.width - insets.left - insets.right
        var area = CGRect(x: insets.left, y: insets.top - bounds.minY, width: width, height: .greatestFiniteMagnitude)
        var options: NSStringDrawingOptions = .usesLineFragmentOrigin
        if !isGrowing {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            text.addAttribute(.paragraphStyle, value: paragraph, range: whole)
            area = CGRect(x: insets.left, y: insets.top, width: width, height: (font ?? .preferredFont(forTextStyle: .body)).lineHeight)
            options.insert(.truncatesLastVisibleLine)
        }
        let image = UIGraphicsImageRenderer(size: bounds.size).image { _ in
            text.draw(with: area, options: options, context: nil)
        }
        return image.cgImage.map { MessageSendPicture(image: $0, frame: frame) }
    }
}
#endif
