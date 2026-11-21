#if os(iOS)
import UIKit

/// UIKit lifts a targeted preview at full size, so a tall message runs under
/// its menu. A preview controller can be any size, so tall messages get one
/// showing a scaled copy of the bubble. The bubble itself still drives the
/// press and lift animations.
@MainActor
enum ContextMenuPreviewFitting {
    /// The share of the safe area a preview may fill; the rest holds the
    /// menu and the reaction bar above it.
    private static let maxHeightFraction: CGFloat = 0.5

    static func fitIfNeeded(_ preview: UITargetedPreview, for configuration: UIContextMenuConfiguration, in window: UIWindow, isOutgoing: Bool) {
        let size = preview.view.bounds.size
        let maxHeight = window.bounds.inset(by: window.safeAreaInsets).height * maxHeightFraction
        guard size.height > maxHeight,
              configuration.responds(to: NSSelectorFromString("setPreviewProvider:")),
              // Keep a preview SwiftUI provides itself.
              configuration.value(forKey: "previewProvider") == nil,
              let snapshot = preview.view.snapshotView(afterScreenUpdates: false) else { return }
        // Keep the message's full width so UIKit places the preview, menu,
        // and reaction bar as it does for any bubble on that side; the copy
        // shrinks against the bubble's own edge.
        let controller = FittedPreviewController(
            content: snapshot,
            size: size,
            preferredSize: CGSize(width: size.width, height: maxHeight),
            isOutgoing: isOutgoing
        )
        let provider: @convention(block) () -> UIViewController? = { controller }
        configuration.setValue(provider, forKey: "previewProvider")
    }
}
#endif
