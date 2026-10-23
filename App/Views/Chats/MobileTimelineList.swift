#if os(iOS)
import SwiftUI

struct MobileTimelineList: UIViewControllerRepresentable {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager

    /// Chronological order; older history prepends and outgoing messages append.
    let rows: [MobileTimelineRow]
    let controller: MobileTimelineController
    let composerHeight: CGFloat
    let onLoadOlder: () -> Void
    let onTapLinkedMessage: (String) -> Void

    func makeCoordinator() -> MobileTimelineCoordinator {
        MobileTimelineCoordinator(controller: controller, chatStore: chatStore, inputManager: inputManager)
    }

    func makeUIViewController(context: Context) -> MobileTimelineViewController {
        let viewController = MobileTimelineViewController(controller: controller)
        context.coordinator.attach(to: viewController.viewport)
        return viewController
    }

    func updateUIViewController(_ viewController: MobileTimelineViewController, context: Context) {
        // SwiftUI's custom iPad composer isn't a UIKit toolbar. Reserve its
        // measured height natively while letting the list draw underneath it.
        if viewController.additionalSafeAreaInsets.bottom != composerHeight {
            viewController.additionalSafeAreaInsets.bottom = composerHeight
        }
        context.coordinator.onLoadOlder = onLoadOlder
        context.coordinator.onTapLinkedMessage = onTapLinkedMessage
        viewController.viewport.collectionView.clipsToBounds = inputManager.sendAnimator.flights.isEmpty
        context.coordinator.update(rows)
    }

    static func dismantleUIViewController(_ viewController: MobileTimelineViewController, coordinator: MobileTimelineCoordinator) {
        viewController.restoreContentScrollView()
    }
}
#endif
