#if os(iOS)
import UIKit
import ObjectiveC

/// SwiftUI shares one interaction across a hosting view. Route its accessory
/// to the pressed message, and forward every other menu/preview callback.
@MainActor
final class ReactionContextMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    private static var associationKey: UInt8 = 0
    private weak var interaction: UIContextMenuInteraction?
    private weak var originalDelegate: (any UIContextMenuInteractionDelegate)?
    private let originalFlags: NSValue
    private let originalInteractionClass: AnyClass
    private let anchors = NSHashTable<ReactionContextMenuBridge.AnchorView>.weakObjects()
    private var selected: ReactionContextMenuBridge.Coordinator?
    private var pendingAction: (() -> Void)?

    private init(interaction: UIContextMenuInteraction, delegate: any UIContextMenuInteractionDelegate, flags: NSValue, originalClass: AnyClass) {
        self.interaction = interaction
        originalDelegate = delegate
        originalFlags = flags
        originalInteractionClass = originalClass
    }

    static func install(on interaction: UIContextMenuInteraction) -> ReactionContextMenuDelegate? {
        if let installed = objc_getAssociatedObject(interaction, &associationKey) as? ReactionContextMenuDelegate,
           interaction.delegate === installed {
            return installed
        }
        guard let original = interaction.delegate,
              let originalClass = object_getClass(interaction),
              let accessoryClass = accessoryInteractionClass(for: originalClass),
              class_getInstanceVariable(UIContextMenuInteraction.self, "_delegate") != nil,
              class_getInstanceVariable(UIContextMenuInteraction.self, "_delegateImplements") != nil,
              let originalFlags = interaction.value(forKey: "delegateImplements") as? NSValue else { return nil }
        let delegate = ReactionContextMenuDelegate(interaction: interaction, delegate: original, flags: originalFlags, originalClass: originalClass)
        // UIKit caches optional callbacks at init; ask UIKit for the exact
        // flags for this proxy, including all forwarded SwiftUI callbacks.
        let configured = UIContextMenuInteraction(delegate: delegate)
        guard let flags = configured.value(forKey: "delegateImplements") as? NSValue else { return nil }
        interaction.setValue(delegate, forKey: "delegate")
        interaction.setValue(flags, forKey: "delegateImplements")
        objc_setAssociatedObject(interaction, &associationKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        object_setClass(interaction, accessoryClass)
        return delegate
    }

    /// The hosting view's interaction creates its presentation machinery before
    /// this adapter attaches. Override its accessory dispatcher on this instance
    /// so that UIKit also requests the newly registered accessory callback.
    private static func accessoryInteractionClass(for base: AnyClass) -> AnyClass? {
        let selector = NSSelectorFromString("_delegate_getAccessoryViewsForConfiguration:")
        guard let method = class_getInstanceMethod(base, selector),
              method_getNumberOfArguments(method) == 3,
              let encoding = method_getTypeEncoding(method), encoding.pointee == 64 else { return nil }
        let name = "RelayReactionAccessory_" + NSStringFromClass(base)
        if let existing = NSClassFromString(name) { return existing }
        guard let subclass = objc_allocateClassPair(base, name, 0) else { return nil }
        let original = method_getImplementation(method)
        let implementation: @convention(block) (UIContextMenuInteraction, UIContextMenuConfiguration) -> NSArray = { interaction, configuration in
            if let delegate = objc_getAssociatedObject(interaction, &associationKey) as? ReactionContextMenuDelegate {
                return delegate.accessories(interaction, configuration: configuration) as NSArray
            }
            typealias Original = @convention(c) (UIContextMenuInteraction, Selector, UIContextMenuConfiguration) -> NSArray?
            return unsafeBitCast(original, to: Original.self)(interaction, selector, configuration) ?? []
        }
        let imp = imp_implementationWithBlock(implementation)
        guard class_addMethod(subclass, selector, imp, encoding) else {
            imp_removeBlock(imp)
            objc_disposeClassPair(subclass)
            return nil
        }
        objc_registerClassPair(subclass)
        return subclass
    }

    func register(_ anchor: ReactionContextMenuBridge.AnchorView) {
        anchors.add(anchor)
    }

    func unregister(_ anchor: ReactionContextMenuBridge.AnchorView) {
        anchors.remove(anchor)
        restoreIfUnused()
    }

    private func restoreIfUnused() {
        guard anchors.allObjects.isEmpty, selected == nil, let interaction else { return }
        if interaction.delegate === self {
            interaction.setValue(originalDelegate, forKey: "delegate")
            interaction.setValue(originalFlags, forKey: "delegateImplements")
            object_setClass(interaction, originalInteractionClass)
        }
        objc_setAssociatedObject(interaction, &Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true { return originalDelegate }
        return super.forwardingTarget(for: selector)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        selected = target(at: location, in: interaction.view)?.coordinator
        let configuration = originalDelegate?.contextMenuInteraction(interaction, configurationForMenuAtLocation: location)
        if configuration == nil { selected = nil }
        return configuration
    }

    @objc(_contextMenuInteraction:accessoriesForMenuWithConfiguration:)
    func accessories(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration) -> [UIView] {
        // SwiftUI can use its private asynchronous configuration callback,
        // bypassing configurationForMenuAtLocation above.
        if selected == nil {
            selected = target(at: interaction.location(in: interaction.view), in: interaction.view)?.coordinator
        }
        if let selected, let accessory = selected.makeAccessory(for: interaction, performAction: { [weak self] action in
            guard let self, self.pendingAction == nil else { return }
            self.pendingAction = action
            interaction.dismissMenu()
        }) {
            return [accessory]
        }
        // Menus outside a registered message keep their original accessories.
        let selector = NSSelectorFromString("_contextMenuInteraction:accessoriesForMenuWithConfiguration:")
        guard let originalDelegate, originalDelegate.responds(to: selector) else { return [] }
        return originalDelegate.perform(selector, with: interaction, with: configuration)?.takeUnretainedValue() as? [UIView] ?? []
    }

    private func target(at point: CGPoint, in view: UIView?) -> ReactionContextMenuBridge.AnchorView? {
        guard let view else { return nil }
        return anchors.allObjects.filter { anchor in
            guard anchor.window != nil, anchor.isDescendant(of: view),
                  anchor.bounds.contains(anchor.convert(point, from: view)) else { return false }
            var ancestor: UIView? = anchor
            while let current = ancestor {
                if current.isHidden || current.alpha < 0.01 { return false }
                ancestor = current.superview
            }
            return true
        }.max { frontOrder(of: $0, within: view).lexicographicallyPrecedes(frontOrder(of: $1, within: view)) }
    }

    /// Overlapping quoted-message copies follow UIKit's front-to-back ordering.
    private func frontOrder(of anchor: UIView, within root: UIView) -> [Int] {
        var view = anchor
        var order: [Int] = []
        while view !== root, let parent = view.superview {
            let siblings = parent.subviews.sorted { $0.layer.zPosition < $1.layer.zPosition }
            order.append(siblings.firstIndex(of: view) ?? 0)
            view = parent
        }
        return order.reversed()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        let preview = originalDelegate?.contextMenuInteraction?(interaction, configuration: configuration, highlightPreviewForItemWithIdentifier: identifier)
        if let preview, let window = interaction.view?.window {
            // A press can end before the menu opens, so look up the message
            // without holding on to it as the selection.
            let pressed = selected ?? target(at: interaction.location(in: interaction.view), in: interaction.view)?.coordinator
            let isOutgoing = pressed?.isOutgoing ?? false
            ContextMenuPreviewFitting.fitIfNeeded(preview, for: configuration, in: window, isOutgoing: isOutgoing)
        }
        return preview
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        originalDelegate?.contextMenuInteraction?(interaction, willEndFor: configuration, animator: animator)
        let action = pendingAction
        let releaseAccessory = selected?.accessoryDismissalCompletion()
        pendingAction = nil
        selected = nil
        let completion = { [weak self] in
            releaseAccessory?()
            action?()
            self?.restoreIfUnused()
        }
        if let animator { animator.addCompletion(completion) }
        else { completion() }
    }
}
#endif
