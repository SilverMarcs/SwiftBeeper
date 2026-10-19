#if os(macOS)
import AppKit

@MainActor
final class MacBubbleView: NSView {
    private let outgoing: Bool
    private let radius: CGFloat

    init(outgoing: Bool, radius: CGFloat = 20) {
        self.radius = radius
        self.outgoing = outgoing
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let cornerRadius = min(radius, bounds.height / 2, bounds.width / 2)
        let shape = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        if outgoing {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            let accent = NSColor.controlAccentColor
            NSGradient(starting: accent.blended(withFraction: 0.12, of: .white) ?? accent, ending: accent)?.draw(in: bounds, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            (dark ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
            shape.fill()
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
#endif
