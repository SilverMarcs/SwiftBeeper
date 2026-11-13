#if os(iOS)
import UIKit

/// The UIKit view behind `ComposerKeyboardAnchor`, which can also call back
/// from inside a Core Animation commit.
final class ComposerKeyboardAnchorView: UIView {
    /// Called in the Core Animation commit's display phase once asked for
    /// with `setNeedsCommitCallback()`: after SwiftUI has laid out and
    /// animated the composer for the frame being committed.
    var onCommit: (() -> Void)? {
        get { hook.onDisplay }
        set { hook.onDisplay = newValue }
    }

    private let hook = DisplayHook()
    private let hookLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        hookLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        hookLayer.opacity = 0
        hookLayer.delegate = hook
        layer.addSublayer(hookLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setNeedsCommitCallback() {
        hookLayer.setNeedsDisplay()
    }

    /// Runs `onDisplay` instead of drawing.
    private final class DisplayHook: NSObject, CALayerDelegate {
        var onDisplay: (() -> Void)?

        func display(_ layer: CALayer) {
            MainActor.assumeIsolated { onDisplay?() }
        }

        func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
            NSNull()
        }
    }
}
#endif
