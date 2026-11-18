#if os(macOS)
import AppKit

extension MacComposerEditor {
    /// Where the bubble's text lines up with the draft, and the draft's
    /// visible lines drawn for the flight. The editor is flipped and fills
    /// its scroll view, so the visible window's top-left is the SwiftUI
    /// frame's.
    /// - Parameter frame: The editor's scroll view frame in SwiftUI's
    ///   global space.
    func sendText(in frame: CGRect) -> (anchor: CGPoint, anchorsLastLine: Bool, picture: MessageSendPicture?) {
        let visible = visibleRect
        let container = textContainerOrigin
        let x = frame.minX + container.x - visible.minX
        let picture = visibleText(in: visible, frame: frame)
        // A draft scrolled down lines up by its last line, which is in view.
        if visible.minY > 0, let layoutManager, let textContainer {
            let bottom = layoutManager.usedRect(for: textContainer).maxY + container.y
            return (CGPoint(x: x, y: frame.minY + bottom - visible.minY), true, picture)
        }
        return (CGPoint(x: x, y: frame.minY + container.y - visible.minY), false, picture)
    }

    /// The draft in the scroll view's visible window as the editor shows
    /// it, in the bubble's white.
    private func visibleText(in visible: CGRect, frame: CGRect) -> MessageSendPicture? {
        guard !string.isEmpty, let textStorage, visible.width > 0, visible.height > 0 else { return nil }
        let text = NSMutableAttributedString(attributedString: textStorage.composerDisplayed)
        text.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: text.length))
        let scale = window?.backingScaleFactor ?? 2
        guard let context = CGContext(
            data: nil, width: Int((visible.width * scale).rounded(.up)), height: Int((visible.height * scale).rounded(.up)),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Top-left origin, as the editor lays its text out.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: visible.height)
        context.scaleBy(x: 1, y: -1)
        let container = textContainerOrigin
        let width = textContainer?.containerSize.width ?? visible.width
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(
            with: CGRect(x: container.x, y: container.y - visible.minY, width: width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin
        )
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().map { MessageSendPicture(image: $0, frame: frame) }
    }
}
#endif
