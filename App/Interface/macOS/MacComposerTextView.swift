#if os(macOS)
import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacComposerTextView: NSTextView {
    var placeholder = "Message" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5), y: textContainerInset.height), withAttributes: [.font: font ?? NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.placeholderTextColor])
        }
    }

    var onSubmit: (() -> Void)?
    var onEditLast: (() -> Void)?
    var onCancel: (() -> Void)?
    var onAttachments: (([URL]) -> Void)?
    var onImage: ((Data, String) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.option) {
            onSubmit?(); return
        }
        if event.keyCode == 126 && string.isEmpty { onEditLast?(); return }
        if event.keyCode == 53 { onCancel?(); return }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            onAttachments?(urls); return
        }
        if let data = board.data(forType: .png) { onImage?(data, "png"); return }
        if let data = board.data(forType: .tiff) { onImage?(data, "tiff"); return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            onAttachments?(urls); return true
        }
        return super.performDragOperation(sender)
    }
}
#endif
