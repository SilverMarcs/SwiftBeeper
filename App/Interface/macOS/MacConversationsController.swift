#if os(macOS)
import AppKit

@MainActor
final class MacConversationsController: NSSplitViewController, NSToolbarDelegate {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private let avatar = MacAvatarView(size: 28)
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let filterItem = NSMenuToolbarItem(itemIdentifier: .init("chatFilter"))
    private let infoItem = NSToolbarItem(itemIdentifier: .init("chatInfo"))
    private var titleWidth: NSLayoutConstraint?
    private var positionedSidebar = false

    init(context: AppContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        let sidebar = NSSplitViewItem(sidebarWithViewController: MacChatListController(context: context))
        sidebar.minimumThickness = 280
        sidebar.maximumThickness = 450
        sidebar.canCollapse = false
        sidebar.preferredThicknessFraction = 340.0 / 1100.0
        addSplitViewItem(sidebar)
        let conversation = MacConversationController(context: context)
        let detail = NSSplitViewItem(viewController: conversation)
        detail.addBottomAlignedAccessoryViewController(conversation.composerAccessory)
        addSplitViewItem(detail)
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .secondaryLabelColor
        filterItem.label = "Filter"
        filterItem.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: nil)
        filterItem.showsIndicator = false
        infoItem.label = "Chat Info"
        infoItem.image = NSImage(systemSymbolName: "info", accessibilityDescription: nil)
        infoItem.target = self; infoItem.action = #selector(showInfo)
        avatar.onOpen = { [weak self] in
            guard let self, let other = context.chats.selectedChat?.otherParticipant else { return }
            (splitViewItems.last?.viewController as? MacConversationController)?.showProfile(other)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else { return }
        let toolbar = NSToolbar(identifier: "RelayConversations")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
        window.titleVisibility = .hidden
        window.toolbar = toolbar
        if !positionedSidebar { splitView.setPosition(340, ofDividerAt: 0); positionedSidebar = true }
        observation.track { [weak self] in self?.renderToolbar() }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        view.window?.toolbar = nil
        view.window?.titleVisibility = .visible
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, filterItem.itemIdentifier, .init("sidebarDivider"), .init("chatTitle"), .flexibleSpace, infoItem.itemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == filterItem.itemIdentifier { return filterItem }
        if identifier == infoItem.itemIdentifier { return infoItem }
        if identifier.rawValue == "sidebarDivider" { return NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: 0) }
        if identifier.rawValue == "chatTitle" {
            let labels = NSStackView(vertical: [titleLabel, subtitle], spacing: 1)
            labels.distribution = .fill
            labels.setHuggingPriority(.required, for: .vertical)
            let header = NSStackView(views: [avatar, labels]); header.spacing = 16; header.alignment = .centerY; header.distribution = .fill; header.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
            titleLabel.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
            subtitle.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
            header.translatesAutoresizingMaskIntoConstraints = false
            titleWidth = header.widthAnchor.constraint(equalToConstant: 220); titleWidth?.isActive = true
            let item = NSToolbarItem(itemIdentifier: identifier); item.view = header; item.isBordered = false
            return item
        }
        return nil
    }

    private func renderToolbar() {
        let store = context.chats
        let chat = store.selectedChat
        view.window?.title = chat?.displayTitle ?? "Relay"
        titleLabel.stringValue = chat?.displayTitle ?? ""
        let count = chat?.participants?.total ?? chat?.participants?.items.count ?? 0
        subtitle.stringValue = chat?.isGroupChat == true && count > 0 ? "\(count) \(count == 1 ? "member" : "members")" : ""
        subtitle.isHidden = subtitle.stringValue.isEmpty
        updateTitleWidth()
        avatar.isHidden = chat == nil
        if let chat { avatar.configure(chat: chat) }
        infoItem.isEnabled = chat != nil
        let menu = NSMenu()
        let inboxes = InboxFilter.allCases.map { ChatFilter.inbox($0) }
        menu.addItem(.sectionHeader(title: "Inboxes"))
        for (index, filter) in (inboxes + store.availableServiceFilters).enumerated() {
            if index == inboxes.count { menu.addItem(.separator()); menu.addItem(.sectionHeader(title: "Services")) }
            menu.addItem(MacActionMenuItem(RelayAction(title: filter.label, symbol: filter.systemImage, selected: filter == store.selectedFilter) {
                store.selectedFilter = filter
                store.searchQuery = ""
                Task { await store.loadChats() }
            }))
        }
        filterItem.menu = menu
    }

    override func viewDidLayout() { super.viewDidLayout(); updateTitleWidth() }
    private func updateTitleWidth() {
        guard let titleWidth else { return }
        let available = max(80, view.bounds.width - (splitView.subviews.first?.bounds.width ?? 340) - 100)
        let natural = 48 + max(titleLabel.intrinsicContentSize.width, subtitle.isHidden ? 0 : subtitle.intrinsicContentSize.width)
        let width = min(available, natural)
        if abs(titleWidth.constant - width) > 0.5 { titleWidth.constant = width }
    }

    @objc private func showInfo() { (splitViewItems.last?.viewController as? MacConversationController)?.showInfo() }
    func focusSearch() { (splitViewItems.first?.viewController as? MacChatListController)?.focusSearch() }
    required init?(coder: NSCoder) { nil }
}
#endif
