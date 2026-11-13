#if os(macOS)
import AppKit

/// Receives one system-picker insertion without routing it through the composer.
final class MacReactionEmojiTextView: NSTextView {
    var onSelection: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var eventMonitor: Any?

    init() {
        super.init(frame: .zero, textContainer: nil)
        drawsBackground = false
        textColor = .clear
        insertionPointColor = .clear
        isRichText = false
        isAutomaticTextCompletionEnabled = false
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, let window else { return }
            guard window.makeFirstResponder(self) else {
                onCancel?()
                return
            }
            installMonitor()
            NSApp.orderFrontCharacterPalette(nil)
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let text = insertString as? String {
            onSelection?(text)
        } else if let text = insertString as? NSAttributedString {
            onSelection?(text.string)
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            Task { @MainActor [weak self] in self?.onCancel?() }
        }
        return resigned
    }

    func stop() {
        onSelection = nil
        onCancel = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    private func installMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, event.window === window else { return event }
            if event.type == .keyDown {
                if event.charactersIgnoringModifiers == "\u{1B}" {
                    onCancel?()
                    return nil
                }
            } else {
                onCancel?()
            }
            return event
        }
    }
}
#endif
