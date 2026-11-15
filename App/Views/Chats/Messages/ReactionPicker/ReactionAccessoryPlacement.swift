#if os(iOS)
import UIKit
import ObjectiveC

/// SwiftUI refreshes the visible UIMenu after entrance. UIKit's refresh layout
/// uses a different preview attachment than its liquid-morph entrance. Keep the
/// message accessory at its initial position while those menu updates run.
@MainActor
enum ReactionAccessoryPlacement {
    private static var refreshKey: UInt8 = 0
    private static var installedKey: UInt8 = 0

    static func viewClass(for base: UIView.Type) -> UIView.Type? {
        let name = "RelayPlacedReactionAccessoryView"
        if let type = NSClassFromString(name) as? UIView.Type { return type }
        guard let type = objc_allocateClassPair(base, name, 0),
              let centerMethod = class_getInstanceMethod(base, NSSelectorFromString("setCenter:")),
              let windowMethod = class_getInstanceMethod(base, NSSelectorFromString("didMoveToWindow")),
              let layoutMethod = class_getInstanceMethod(base, NSSelectorFromString("layoutSubviews")) else { return nil }

        let centerSelector = NSSelectorFromString("setCenter:")
        let originalCenter = method_getImplementation(centerMethod)
        let center: @convention(block) (UIView, CGPoint) -> Void = { view, point in
            if let window = view.window,
               (objc_getAssociatedObject(window, &refreshKey) as? NSNumber)?.boolValue == true,
               window.bounds.contains(view.convert(view.bounds, to: window)) {
                return
            }
            typealias Setter = @convention(c) (UIView, Selector, CGPoint) -> Void
            unsafeBitCast(originalCenter, to: Setter.self)(view, centerSelector, point)
        }
        class_addMethod(type, centerSelector, imp_implementationWithBlock(center), method_getTypeEncoding(centerMethod))

        for (selector, method) in [(NSSelectorFromString("didMoveToWindow"), windowMethod),
                                   (NSSelectorFromString("layoutSubviews"), layoutMethod)] {
            let original = method_getImplementation(method)
            let lifecycle: @convention(block) (UIView) -> Void = { view in
                typealias Callback = @convention(c) (UIView, Selector) -> Void
                unsafeBitCast(original, to: Callback.self)(view, selector)
                installRefreshGuard(for: view)
            }
            class_addMethod(type, selector, imp_implementationWithBlock(lifecycle), method_getTypeEncoding(method))
        }
        objc_registerClassPair(type)
        return type as? UIView.Type
    }

    private static func installRefreshGuard(for accessory: UIView) {
        guard objc_getAssociatedObject(accessory, &installedKey) == nil,
              let window = accessory.window else { return }
        let selector = NSSelectorFromString("replaceVisibleMenu:withMenu:alongsideAnimations:")
        var views: [UIView] = [window]
        var installed = false
        while let view = views.popLast() {
            views.append(contentsOf: view.subviews)
            guard let base = object_getClass(view), view.responds(to: selector) else { continue }
            let name = NSStringFromClass(base)
            if name.hasPrefix("RelayReactionMenuRefresh_") { installed = true; continue }
            if let type = refreshViewClass(for: base, selector: selector) {
                object_setClass(view, type)
                installed = true
            }
        }
        if installed {
            objc_setAssociatedObject(accessory, &installedKey, true as NSNumber, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private static func refreshViewClass(for base: AnyClass, selector: Selector) -> AnyClass? {
        let name = "RelayReactionMenuRefresh_" + NSStringFromClass(base)
        if let type = NSClassFromString(name) { return type }
        guard let method = class_getInstanceMethod(base, selector),
              method_getNumberOfArguments(method) == 5,
              let encoding = method_getTypeEncoding(method), encoding.pointee == 118,
              let type = objc_allocateClassPair(base, name, 0) else { return nil }
        let original = method_getImplementation(method)
        let refresh: @convention(block) (UIView, AnyObject?, AnyObject?, AnyObject?) -> Void = { view, old, new, animations in
            let window = view.window
            let previous = window.flatMap { objc_getAssociatedObject($0, &refreshKey) }
            if let window {
                objc_setAssociatedObject(window, &refreshKey, true as NSNumber, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            defer {
                if let window {
                    objc_setAssociatedObject(window, &refreshKey, previous, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            }
            typealias Refresh = @convention(c) (UIView, Selector, AnyObject?, AnyObject?, AnyObject?) -> Void
            unsafeBitCast(original, to: Refresh.self)(view, selector, old, new, animations)
        }
        let imp = imp_implementationWithBlock(refresh)
        guard class_addMethod(type, selector, imp, encoding) else {
            imp_removeBlock(imp)
            objc_disposeClassPair(type)
            return nil
        }
        objc_registerClassPair(type)
        return type
    }
}
#endif
