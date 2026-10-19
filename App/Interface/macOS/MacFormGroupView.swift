#if os(macOS)
import AppKit

@MainActor
final class MacFormGroupView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 8
    }
    required init?(coder: NSCoder) { nil }
    override func updateLayer() { layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
#endif
