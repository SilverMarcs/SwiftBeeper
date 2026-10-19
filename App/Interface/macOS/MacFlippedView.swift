#if os(macOS)
import AppKit

@MainActor
final class MacFlippedView: NSView {
    override var isFlipped: Bool { true }
}
#endif
