#if os(iOS)
import UIKit

@MainActor
final class MobileChatListController: UICollectionViewController, UISearchResultsUpdating, UISearchBarDelegate {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private let search = UISearchController(searchResultsController: nil)
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
    private var displayed: [Chat] = []
    private let filter = UIBarButtonItem(title: "Filter", image: UIImage(systemName: "line.3.horizontal.decrease"), target: nil, action: nil)
    private let status = UILabel()
    var onSelect: (() -> Void)?
    var onAppear: (() -> Void)?

    init(context: AppContext) {
        self.context = context
        super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: .init(appearance: UIDevice.current.userInterfaceIdiom == .pad ? .sidebar : .plain)))
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Chats"
        navigationController?.navigationBar.prefersLargeTitles = true
        var configuration = UICollectionLayoutListConfiguration(appearance: UIDevice.current.userInterfaceIdiom == .pad ? .sidebar : .plain)
        configuration.showsSeparators = true
        configuration.itemSeparatorHandler = { _, defaults in
            var separators = defaults
            separators.topSeparatorVisibility = .hidden
            return separators
        }
        configuration.leadingSwipeActionsConfigurationProvider = { [weak self] index in self?.swipeActions(at: index, leading: true) }
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] index in self?.swipeActions(at: index, leading: false) }
        collectionView.setCollectionViewLayout(UICollectionViewCompositionalLayout.list(using: configuration), animated: false)
        collectionView.register(MobileChatCell.self, forCellWithReuseIdentifier: "chat")
        collectionView.keyboardDismissMode = .onDrag
        search.searchResultsUpdater = self; search.searchBar.delegate = self
        search.obscuresBackgroundDuringPresentation = false; search.hidesNavigationBarDuringPresentation = false
        definesPresentationContext = true; search.searchBar.placeholder = "Search chats"
        navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
        let settings = UIBarButtonItem(image: UIImage(systemName: "gear"), primaryAction: UIAction(title: "Settings") { [weak self] _ in self?.showSettings() })
        if UIDevice.current.userInterfaceIdiom == .phone {
            navigationItem.largeTitleDisplayMode = .inline
            navigationItem.preferredSearchBarPlacement = .integrated
            navigationItem.searchBarPlacementAllowsToolbarIntegration = true
            navigationItem.rightBarButtonItem = settings
            toolbarItems = [navigationItem.searchBarPlacementBarButtonItem, UIBarButtonItem(systemItem: .fixedSpace), filter]
        } else {
            navigationItem.largeTitleDisplayMode = .never
            navigationItem.leftBarButtonItem = settings
            navigationItem.rightBarButtonItem = filter
        }
        status.font = .preferredFont(forTextStyle: .body); status.textColor = .secondaryLabel; status.textAlignment = .center; status.numberOfLines = 0
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { [weak self] collection, index, id in
            guard let self, let chat = context.chats.chat(byID: id), let cell = collection.dequeueReusableCell(withReuseIdentifier: "chat", for: index) as? MobileChatCell else { return nil }
            cell.configure(chat); return cell
        }
        observation.track { [weak self] in self?.render() }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onAppear?()
        navigationController?.setToolbarHidden(UIDevice.current.userInterfaceIdiom != .phone, animated: animated)
    }
    private func render() {
        let store = context.chats
        let chats = store.displayedChats
        if chats != displayed {
            let old = Set(displayed.map(\.id)); displayed = chats
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>(); snapshot.appendSections([0]); snapshot.appendItems(chats.map(\.id))
            snapshot.reconfigureItems(chats.map(\.id).filter { old.contains($0) })
            dataSource?.apply(snapshot, animatingDifferences: false)
        }
        if let id = store.selectedChatID, let index = dataSource?.indexPath(for: id), splitViewController?.isCollapsed == false { collectionView.selectItem(at: index, animated: false, scrollPosition: []) }
        status.text = store.chatsError ?? (store.isSearching ? "Searching…" : (store.isLoadingChats ? "Loading conversations…" : "No conversations"))
        collectionView.backgroundView = chats.isEmpty ? status : nil
        let filters = InboxFilter.allCases.map { ChatFilter.inbox($0) }
        func actions(_ filters: [ChatFilter]) -> [UIAction] {
            filters.map { item in
                UIAction(title: item.label, image: UIImage(systemName: item.systemImage), state: item == store.selectedFilter ? .on : .off) { [weak self] _ in
                    guard let self else { return }
                    store.selectedFilter = item; search.searchBar.text = ""; search.isActive = false
                    Task { await store.loadChats() }
                }
            }
        }
        filter.menu = UIMenu(children: [UIMenu(title: "Inboxes", options: .displayInline, children: actions(filters)), UIMenu(title: "Services", options: .displayInline, children: actions(store.availableServiceFilters))])
    }
    func closeSearch() {
        search.searchBar.text = ""
        search.isActive = false
        search.searchBar.resignFirstResponder()
    }
    func updateSearchResults(for searchController: UISearchController) {
        context.chats.searchQuery = searchController.searchBar.text ?? ""
        if context.chats.searchQuery.isBlank { context.chats.submitSearch() }
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { context.chats.submitSearch(); searchBar.resignFirstResponder() }
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource?.itemIdentifier(for: indexPath) else { return }
        context.chats.selectedChatID = id; search.searchBar.resignFirstResponder(); onSelect?()
    }
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating,
              context.chats.searchQuery.isBlank,
              scrollView.contentOffset.y + scrollView.bounds.height > scrollView.contentSize.height - 300 else { return }
        Task { await context.chats.loadMoreChats() }
    }
    override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let id = dataSource?.itemIdentifier(for: indexPath), let chat = context.chats.chat(byID: id) else { return nil }
        return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let sections = ConversationActions.chat(chat, store: context.chats).map { action in
                UIMenu(options: .displayInline, children: [action.uiAction])
            }
            return UIMenu(children: sections)
        }
    }
    private func swipeActions(at indexPath: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        guard let id = dataSource?.itemIdentifier(for: indexPath), let chat = context.chats.chat(byID: id) else { return nil }
        let actions = ConversationActions.chat(chat, store: context.chats).filter { ($0.title == "Mark Read") == leading }.map { action in
            let swipe = UIContextualAction(style: .normal, title: nil) { _, _, done in action.perform(); done(true) }
            swipe.image = UIImage(systemName: action.symbol); swipe.backgroundColor = action.title == "Archive" ? .systemOrange : (action.title == "Mute" || action.title == "Unmute" ? .systemPurple : .systemBlue)
            return swipe
        }
        return actions.isEmpty ? nil : UISwipeActionsConfiguration(actions: actions)
    }
    private func showSettings() {
        let controller = UINavigationController(rootViewController: MobileSettingsController(context: context))
        controller.modalPresentationStyle = .formSheet; present(controller, animated: true)
    }
}
#endif
