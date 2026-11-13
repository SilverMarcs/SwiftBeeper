#if os(macOS)
import AppKit
import SwiftUI

/// The text view behind `MacComposerTextView`: plain text in the body font,
/// with a placeholder, focus reported as it moves, and Escape left to the
/// window, as the `TextField` it replaced did.
final class MacComposerEditor: NSTextView {
    /// Shown while the draft is empty.
    var placeholder = "" {
        didSet {
            guard placeholder != oldValue else { return }
            needsDisplay = true
            setAccessibilityPlaceholderValue(placeholder)
        }
    }

    /// Called with `true` when the editor becomes first responder, and
    /// `false` when it stops being one.
    var onFocusChange: ((Bool) -> Void)?

    static let font = NSFont.preferredFont(forTextStyle: .body)

    convenience init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = Self.lineFragmentPadding
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)

        font = Self.font
        textColor = .textColor
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainerInset = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        typingAttributes = ComposerMentionStyle.plainAttributes(font: Self.font, textColor: .textColor)
    }

    /// The surrounding SwiftUI padding already matches the plain `TextField`.
    static let lineFragmentPadding: CGFloat = 0

    /// Only text drags land in the draft; files and images fall through to
    /// the timeline, which attaches them.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    /// A text view completes words on Escape; the composer leaves it to the
    /// window, where Cancel Reply and the other cancel shortcuts live.
    override func cancelOperation(_ sender: Any?) {
        nextResponder?.cancelOperation(sender)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let origin = NSPoint(x: textContainerInset.width + Self.lineFragmentPadding, y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: font ?? Self.font,
            .foregroundColor: NSColor(Color.secondary),
        ])
    }

    /// The editor's height at `width` for `text`: its wrapped lines, from one
    /// up to `maximumLines`, past which it scrolls.
    static func fittingHeight(of text: String, width: CGFloat, maximumLines: Int) -> CGFloat {
        let storage = NSTextStorage(string: text.isEmpty ? " " : text, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = lineFragmentPadding
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        // A trailing newline starts a line the used rect doesn't include.
        var height = layoutManager.usedRect(for: container).height
        if text.hasSuffix("\n") { height += lineHeight }
        return ceil(min(max(height, lineHeight), lineHeight * CGFloat(maximumLines)))
    }
}
#endif
