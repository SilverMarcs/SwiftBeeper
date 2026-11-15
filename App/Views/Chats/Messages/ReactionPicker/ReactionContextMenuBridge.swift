#if os(iOS)
import SwiftUI
import UIKit

/// Registers this row with the context-menu interaction shared by its host.
struct ReactionContextMenuBridge: UIViewRepresentable {
    let message: Message
    let chat: Chat
    let environment: EnvironmentValues
    @Binding var isInstalled: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.update(self)
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
        view.coordinator = nil
    }

    final class AnchorView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(from: self)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.attach(from: self)
        }
    }

    @MainActor
    final class Coordinator {
        private var source: ReactionContextMenuBridge?
        private weak var anchor: AnchorView?
        private weak var delegate: ReactionContextMenuDelegate?
        private var accessory: UIView?
        private var host: UIHostingController<ReactionAccessoryBar>?
        private var installationTask: Task<Void, Never>?

        func update(_ source: ReactionContextMenuBridge) {
            // The accessory snapshots the latest source for each presentation.
            self.source = source
        }

        func attach(from anchor: AnchorView) {
            guard anchor.window != nil, let source else { return }
            var ancestor = anchor.superview
            // SwiftUI's interaction lives on the host above the scroll view,
            // rather than on each message's native background view.
            while let view = ancestor {
                if let interaction = view.interactions.compactMap({ $0 as? UIContextMenuInteraction }).first {
                    guard let accessory = accessory ?? ReactionContextMenuAccessory.make(isOutgoing: source.message.isSender),
                          let installed = ReactionContextMenuDelegate.install(on: interaction) else {
                        detach()
                        setInstalled(false)
                        return
                    }
                    if delegate !== installed || self.anchor !== anchor {
                        installed.register(anchor)
                        detach()
                        self.anchor = anchor
                        delegate = installed
                    }
                    self.accessory = accessory
                    setInstalled(true)
                    return
                }
                ancestor = view.superview
            }
            detach()
            setInstalled(false)
        }

        func detach() {
            installationTask?.cancel()
            if let anchor { delegate?.unregister(anchor) }
            delegate = nil
            anchor = nil
            accessory = nil
            host = nil
        }

        private func setInstalled(_ installed: Bool) {
            installationTask?.cancel()
            guard source?.isInstalled != installed else { return }
            installationTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                self?.source?.isInstalled = installed
            }
        }

        func makeAccessory(for interaction: UIContextMenuInteraction, performAction: @escaping (@escaping () -> Void) -> Void) -> UIView? {
            guard let source, let view = interaction.view,
                  let accessory = ReactionContextMenuAccessory.make(isOutgoing: source.message.isSender) else { return nil }
            // UIKit transforms accessory views during dismissal. A fresh view
            // avoids carrying that transform into the next presentation.
            self.accessory = accessory
            let host = UIHostingController(rootView: bar(performAction: performAction))
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
            // UIKit places the accessory with the preview near screen edges.
            // Scrolling keeps all reactions reachable at large text sizes.
            let width = min(380, max(1, (view.window?.bounds.width ?? view.bounds.width) - 32))
            let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            accessory.frame = CGRect(origin: .zero, size: CGSize(width: min(width, size.width), height: size.height))
            host.view.frame = accessory.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            accessory.subviews.forEach { $0.removeFromSuperview() }
            accessory.addSubview(host.view)
            host.view.layoutIfNeeded()
            self.host = host
            return accessory
        }

        private func bar(performAction: @escaping (@escaping () -> Void) -> Void) -> ReactionAccessoryBar {
            guard let source else { preconditionFailure("Missing reaction menu source") }
            return ReactionAccessoryBar(message: source.message, chat: source.chat, environment: source.environment, performAction: performAction)
        }

        func accessoryDismissalCompletion() -> () -> Void {
            let dismissedAccessory = accessory
            let dismissedHost = host
            return { [weak self] in
                dismissedAccessory?.subviews.forEach { $0.removeFromSuperview() }
                // Reopening a menu can create its next host before the old
                // dismissal animation completes. Release only the old host.
                if self?.host === dismissedHost {
                    self?.host = nil
                    self?.accessory = nil
                }
            }
        }
    }
}
#endif
