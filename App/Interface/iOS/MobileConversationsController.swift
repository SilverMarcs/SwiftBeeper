#if os(iOS)
import UIKit

@MainActor
final class MobileConversationsController: UISplitViewController, UISplitViewControllerDelegate {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private let list: MobileChatListController
    private let detail: MobileConversationController
    private let primary: UINavigationController
    private let secondary: UINavigationController
    private var displayedChatID: String?
    private var notificationSelectionID: UUID?

    init(context: AppContext) {
        self.context = context
        list = MobileChatListController(context: context)
        detail = MobileConversationController(context: context)
        primary = UINavigationController(rootViewController: list)
        secondary = UINavigationController(rootViewController: detail)
        super.init(style: .doubleColumn)
        delegate = self
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        if UIDevice.current.userInterfaceIdiom == .pad {
            presentsWithGesture = false
            displayModeButtonVisibility = .never
            showsSecondaryOnlyButton = false
        }
        minimumPrimaryColumnWidth = 280; maximumPrimaryColumnWidth = 420
        preferredPrimaryColumnWidth = 340
        setViewController(primary, for: .primary)
        setViewController(secondary, for: .secondary)
        list.onSelect = { [weak self] in self?.show(.secondary) }
        list.onAppear = { [weak self] in
            guard let self, isCollapsed else { return }
            detail.closeComposer()
        }
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad()
        observation.track { [weak self] in
            guard let self else { return }
            showNotificationSelection()
            let id = context.chats.selectedChatID
            if id != displayedChatID {
                displayedChatID = id
                if id == nil { show(.primary) }
            }
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showNotificationSelection()
    }

    private func showNotificationSelection() {
        // A cold-launch destination can resolve before this controller is in a
        // window. Keep it unconsumed until UIKit can safely show the detail.
        guard context.isForeground,
              let requestID = context.chats.notificationSelectionID,
              requestID != notificationSelectionID,
              context.chats.selectedChatID != nil,
              viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive else { return }
        notificationSelectionID = requestID
        list.closeSearch()
        show(.secondary)
    }

    func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposed: UISplitViewController.Column) -> UISplitViewController.Column {
        context.chats.selectedChatID == nil ? .primary : .secondary
    }
}
#endif
