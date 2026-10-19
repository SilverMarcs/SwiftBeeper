#if os(macOS)
import AppKit

@MainActor
final class MacChatListController: NSViewController, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let search = NSSearchField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var dataSource: NSTableViewDiffableDataSource<Int, String>?
    private var displayed: [Chat] = []
    private var scrollObserver: NSObjectProtocol?
    private var isApplyingSnapshot = false
    private var isUpdatingLayout = false
    private var previousOriginY: CGFloat = 0

    init(context: AppContext) { self.context = context; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }
    override func loadView() { let background = NSVisualEffectView(); background.material = .sidebar; background.blendingMode = .withinWindow; background.state = .active; view = background }

    override func viewDidLoad() {
        super.viewDidLoad()
        search.placeholderString = "Search chats"
        search.controlSize = .large
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.target = self; search.action = #selector(submitSearch)
        status.font = .preferredFont(forTextStyle: .caption1); status.textColor = .secondaryLabelColor
        let top = NSStackView(vertical: [search, status], spacing: 4)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("chat")); table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 64; table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .sourceList; table.delegate = self
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.gridColor = .separatorColor
        let menu = NSMenu(); menu.delegate = self; table.menu = menu
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        table.backgroundColor = .clear
        scroll.automaticallyAdjustsContentInsets = false
        let root = NSStackView(vertical: [top, scroll]); root.spacing = 9; root.alignment = .centerX
        view.addSubview(root); root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: view.leadingAnchor), root.trailingAnchor.constraint(equalTo: view.trailingAnchor), root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 9), root.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        for child in [top, scroll] { child.widthAnchor.constraint(equalTo: root.widthAnchor, constant: child === top ? -20 : 0).isActive = true }
        for child in [search, status] { child.widthAnchor.constraint(equalTo: top.widthAnchor).isActive = true }
        dataSource = NSTableViewDiffableDataSource<Int, String>(tableView: table) { [weak self] table, _, _, id in
            guard let self, let chat = context.chats.chat(byID: id) else { return NSView() }
            let cell = (table.makeView(withIdentifier: NSUserInterfaceItemIdentifier("chat"), owner: nil) as? MacChatRowView) ?? MacChatRowView()
            cell.identifier = NSUserInterfaceItemIdentifier("chat")
            cell.configure(chat)
            return cell
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.loadNextPageIfNeeded() }
        }
        observation.track { [weak self] in self?.render() }
    }

    private func render() {
        isUpdatingLayout = true
        defer { isUpdatingLayout = false }
        let store = context.chats
        let chats = store.displayedChats
        if chats != displayed {
            let oldIDs = Set(displayed.map(\.id))
            displayed = chats
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0]); snapshot.appendItems(chats.map(\.id))
            snapshot.reloadItems(chats.map(\.id).filter { oldIDs.contains($0) })
            isApplyingSnapshot = true
            dataSource?.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                self.isUpdatingLayout = true
                self.isApplyingSnapshot = false
                self.syncSelection()
                self.isUpdatingLayout = false
            }
        }
        if !isApplyingSnapshot { syncSelection() }
        status.stringValue = store.chatsError ?? (store.isSearching ? "Searching…" : (store.isLoadingChats && chats.isEmpty ? "Loading conversations…" : (chats.isEmpty ? "No conversations" : "")))
        status.isHidden = status.stringValue.isEmpty
    }

    private func syncSelection() {
        let selected = displayed.firstIndex { $0.id == context.chats.selectedChatID }
        if let selected, table.selectedRow != selected { table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false) }
        else if selected == nil, table.selectedRow != -1 { table.deselectAll(nil) }
    }

    func focusSearch() { view.window?.makeFirstResponder(search) }

    @objc private func submitSearch() {
        context.chats.searchQuery = search.stringValue
        context.chats.submitSearch()
    }

    func controlTextDidChange(_ notification: Notification) {
        context.chats.searchQuery = search.stringValue
        if search.stringValue.isBlank { context.chats.submitSearch() }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingLayout, !isApplyingSnapshot, displayed.indices.contains(table.selectedRow) else { return }
        context.chats.selectedChatID = displayed[table.selectedRow].id
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("chatRow")
        let view = (tableView.makeView(withIdentifier: identifier, owner: nil) as? MacChatTableRowView) ?? MacChatTableRowView()
        view.identifier = identifier
        return view
    }

    private func loadNextPageIfNeeded() {
        let origin = scroll.contentView.bounds.minY
        let movedDown = origin > previousOriginY
        previousOriginY = origin
        guard !isUpdatingLayout, !isApplyingSnapshot, movedDown, context.chats.searchQuery.isBlank,
              scroll.contentView.bounds.maxY >= table.bounds.height - 220 else { return }
        Task { await context.chats.loadMoreChats() }
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard displayed.indices.contains(row) else { return [] }
        return ConversationActions.chat(displayed[row], store: context.chats).filter { (edge == .leading) == ($0.title == "Mark Read") }.map { action in
            let swipe = NSTableViewRowAction(style: .regular, title: "") { _, _ in action.perform() }
            swipe.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            swipe.backgroundColor = action.title == "Archive" ? .systemOrange : (action.title == "Mute" || action.title == "Unmute" ? .systemPurple : .systemBlue)
            return swipe
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard displayed.indices.contains(table.clickedRow) else { return }
        for action in ConversationActions.chat(displayed[table.clickedRow], store: context.chats) {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(MacActionMenuItem(action))
        }
    }

    isolated deinit { if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) } }
}
#endif
