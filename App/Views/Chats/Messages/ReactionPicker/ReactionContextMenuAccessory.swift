#if os(iOS)
import UIKit
import ObjectiveC

/// Runtime-only access avoids linking a private class and lets unsupported
/// UIKit versions keep the ordinary SwiftUI reaction palette.
@MainActor
enum ReactionContextMenuAccessory {
    static func make(isOutgoing: Bool) -> UIView? {
        guard let type = NSClassFromString("_UIContextMenuAccessoryView") as? UIView.Type,
              ["setLocation:", "setAnchor:", "setOffset:", "setTrackingAxis:"].allSatisfy({
                  type.instancesRespond(to: NSSelectorFromString($0))
              }),
              let getter = class_getInstanceMethod(type, NSSelectorFromString("anchor")) else { return nil }
        let encoding = method_copyReturnType(getter)
        defer { free(encoding) }

        // Verify the documented runtime layout before passing a struct to KVC.
        let signature = String(cString: encoding)
        guard signature == "{?=QQddq}" || signature == "{?=qqddq}" else { return nil }
        var anchor = Anchor(attachment: 1, alignment: isOutgoing ? 8 : 2)
        let anchorValue = withUnsafePointer(to: &anchor) { NSValue(bytes: $0, objCType: encoding) }
        guard let placedType = ReactionAccessoryPlacement.viewClass(for: type) else { return nil }
        let view = placedType.init(frame: .zero)
        view.setValue(1, forKey: "location") // Relative to the message preview.
        view.setValue(anchorValue, forKey: "anchor") // Above the preview.
        view.setValue(NSValue(cgPoint: CGPoint(x: 0, y: -12)), forKey: "offset")
        view.setValue(0, forKey: "trackingAxis") // Keep the bar stable while the preview tracks the touch.
        return view
    }

    private struct Anchor {
        var attachment: UInt64
        var alignment: UInt64
        var attachmentOffset: Double = 0
        var alignmentOffset: Double = 0
        var gravity: Int64 = 0
    }
}
#endif
