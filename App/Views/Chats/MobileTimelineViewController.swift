#if os(iOS)
import UIKit

/// Makes the native timeline discoverable to the system navigation and toolbar
/// edge effects without attaching interactions to SwiftUI's private bar views.
final class MobileTimelineViewController: UIViewController {
    let viewport = MobileTimelineViewport()
    private let controller: MobileTimelineController
    private weak var barOwner: UIViewController?
    private weak var previousTopScrollView: UIScrollView?
    private weak var previousBottomScrollView: UIScrollView?

    init(controller: MobileTimelineController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = viewport
        setContentScrollView(viewport.collectionView, for: .all)
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        registerContentScrollView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        controller.performPendingRequest()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        controller.cancelAutomaticScroll()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            restoreContentScrollView()
        }
    }

    private func registerContentScrollView() {
        // The navigation controller observes its immediate content controller.
        // SwiftUI may insert containment controllers above this representable.
        var owner = parent
        while let ancestor = owner?.parent,
              !(ancestor is UINavigationController),
              !(ancestor is UISplitViewController),
              !(ancestor is UITabBarController) {
            owner = ancestor
        }
        guard let owner, owner !== barOwner else { return }
        restoreContentScrollView()
        barOwner = owner
        previousTopScrollView = owner.contentScrollView(for: .top)
        previousBottomScrollView = owner.contentScrollView(for: .bottom)
        owner.setContentScrollView(viewport.collectionView, for: .all)
    }

    func restoreContentScrollView() {
        guard let owner = barOwner else { return }
        if owner.contentScrollView(for: .top) === viewport.collectionView {
            owner.setContentScrollView(previousTopScrollView, for: .top)
        }
        if owner.contentScrollView(for: .bottom) === viewport.collectionView {
            owner.setContentScrollView(previousBottomScrollView, for: .bottom)
        }
        barOwner = nil
        previousTopScrollView = nil
        previousBottomScrollView = nil
    }
}
#endif
