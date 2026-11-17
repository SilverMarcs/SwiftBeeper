#if os(macOS)
import AppKit
import SwiftUI

/// The window behind the macOS mention menu: borderless, in the menu
/// material, and never key, so the composer keeps the keyboard while the
/// menu is up and typing carries on narrowing it.
final class MentionMenuPanel: NSPanel {
    let hostingView: MentionMenuHostingView

    init(rootView: MentionMenuView) {
        hostingView = MentionMenuHostingView(rootView: rootView)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true

        let material = NSVisualEffectView()
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = Self.mask(cornerRadius: MentionMenuMetrics.cornerRadius)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: material.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        contentView = material
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// A rounded rect that stretches to any size, keeping its corners.
    private static func mask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
#endif
