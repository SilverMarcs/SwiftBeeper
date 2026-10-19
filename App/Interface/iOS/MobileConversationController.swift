#if os(iOS)
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

@MainActor
final class MobileConversationController: UIViewController, UITableViewDelegate, UIDocumentPickerDelegate, PHPickerViewControllerDelegate, QLPreviewControllerDataSource, UISearchResultsUpdating, UISearchBarDelegate {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private let searchComposer = UISearchController(searchResultsController: nil)
    private let titleControl = MobileConversationHeaderView()
    private let table = UITableView(frame: .zero, style: .plain)
    private let status = UILabel()
    private let loading = UIActivityIndicatorView(style: .medium)
    private lazy var statusStack = UIStackView(vertical: [status, loading], spacing: 4)
    private lazy var composer = MobileComposerView(context: context)
    private var dataSource: UITableViewDiffableDataSource<Int, String>?
    private var rows: [TimelineRow] = []
    private var rowsByID: [String: TimelineRow] = [:]
    private var chatID: String?
    private var firstUnreadID: String?
    private var hasPositioned = false
    private var paginationTask: Task<Void, Never>?
    private var pendingScrollToBottom = false
    private var sendScrollTask: Task<Void, Never>?
    private var sendScrollRevision = UUID()
    private var attachmentChatID: String?
    private var previewURL: URL?
    private var isApplyingSnapshot = false
    private var snapshotRevision = UUID()
    private var keepsBottomVisible = true
    private var keepsComposerOpen = false

    init(context: AppContext) { self.context = context; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "info"), primaryAction: UIAction(title: "Chat Info") { [weak self] _ in self?.showInfo() })
        navigationItem.title = ""
        if let chat = context.chats.selectedChat { titleControl.configure(chat) }
        titleControl.addAction(UIAction { [weak self] _ in
            guard let self, let chat = context.chats.selectedChat else { return }
            if chat.isSingleChat, let participant = chat.otherParticipant { showProfile(participant) } else { showInfo() }
        }, for: .touchUpInside)
        if UIDevice.current.userInterfaceIdiom == .phone {
            navigationItem.titleView = titleControl
            searchComposer.obscuresBackgroundDuringPresentation = false
            searchComposer.hidesNavigationBarDuringPresentation = false
            searchComposer.searchResultsUpdater = self; searchComposer.searchBar.delegate = self
            searchComposer.searchBar.searchTextField.returnKeyType = .send
            searchComposer.searchBar.searchTextField.enablesReturnKeyAutomatically = true
            navigationItem.preferredSearchBarPlacement = .integrated
            navigationItem.searchBarPlacementAllowsToolbarIntegration = true
            let attach = UIBarButtonItem(image: UIImage(systemName: "plus"), menu: UIMenu(children: [UIAction(title: "Photos Library", image: UIImage(systemName: "photo.on.rectangle.angled")) { [weak self] _ in self?.choosePhotos() }, UIAction(title: "Attach Files", image: UIImage(systemName: "paperclip")) { [weak self] _ in self?.chooseFiles() }]))
            toolbarItems = [attach, .flexibleSpace(), navigationItem.searchBarPlacementBarButtonItem]
            definesPresentationContext = true
        } else {
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: titleControl)
            navigationItem.leftItemsSupplementBackButton = true
        }
        table.delegate = self; table.separatorStyle = .none
        table.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .none : .interactive
        table.contentInsetAdjustmentBehavior = .always
        table.alwaysBounceVertical = true
        table.bouncesHorizontally = false
        table.isDirectionalLockEnabled = true
        table.showsHorizontalScrollIndicator = false
        setContentScrollView(table, for: .all)
        table.estimatedRowHeight = 90; table.rowHeight = UITableView.automaticDimension
        table.register(MobileMessageCell.self, forCellReuseIdentifier: "message")
        status.numberOfLines = 0; status.textAlignment = .center; status.textColor = .secondaryLabel; status.font = .preferredFont(forTextStyle: .body)
        let statusTap = UITapGestureRecognizer(target: self, action: #selector(reloadMessages)); status.addGestureRecognizer(statusTap); status.isUserInteractionEnabled = true
        statusStack.alignment = .center
        for child in [table, statusStack, composer] { view.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            statusStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), statusStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), statusStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor), table.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            composer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), composer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        let bottomEdge = UIScrollEdgeElementContainerInteraction()
        bottomEdge.scrollView = table; bottomEdge.edge = .bottom
        composer.addInteraction(bottomEdge)
        if UIDevice.current.userInterfaceIdiom == .pad {
            table.bottomEdgeEffect.isHidden = true
            // To restore the native bottom blur, remove the line above and enable:
            // table.bottomEdgeEffect.style = .soft
        }
        composer.onSubmit = { [weak self] in self?.requestSendScroll() }
        composer.onFocus = { [weak self] in self?.scrollToBottom() }
        composer.onRequestFocus = { [weak self] in
            guard let self else { return }; searchComposer.isActive = true; searchComposer.searchBar.becomeFirstResponder()
        }
        composer.onChooseFiles = { [weak self] in self?.chooseFiles() }
        composer.onChoosePhotos = { [weak self] in self?.choosePhotos() }
        dataSource = UITableViewDiffableDataSource<Int, String>(tableView: table) { [weak self] table, index, id in
            guard let self, let row = rowsByID[id], let chat = context.chats.selectedChat,
                  let cell = table.dequeueReusableCell(withIdentifier: "message", for: index) as? MobileMessageCell else { return nil }
            cell.configure(row, chat: chat, context: context)
            cell.onJump = { [weak self] in self?.jump(to: $0) }
            cell.onProfile = { [weak self] in self?.showProfile($0) }
            cell.onPreview = { [weak self] in self?.preview($0) }
            return cell
        }
        observation.track { [weak self] in self?.render() }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Selection observation is deferred; prepare the header before the
        // navigation transition measures its title view.
        if let chat = context.chats.selectedChat {
            titleControl.configure(chat)
            titleControl.isHidden = false
        }
        navigationController?.setToolbarHidden(UIDevice.current.userInterfaceIdiom != .phone, animated: animated)
    }
    func updateSearchResults(for searchController: UISearchController) {
        let draft = searchController.searchBar.text ?? ""
        if draft != context.composer.draft { context.composer.draft = draft }
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard !context.composer.sendButtonDisabled, !context.composer.cannotMessage else { return }
        context.composer.handleSubmit(); requestSendScroll()
    }
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        keepsComposerOpen = true
        if !context.composer.hasActiveComposerAction { scrollToBottom() }
    }
    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        // Send clears the draft, but the composing session ends only on Close
        // or when leaving this screen.
        !keepsComposerOpen
    }
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        // Closing the keyboard must preserve the message draft.
        closeComposer()
        searchBar.text = context.composer.draft
    }
    func closeComposer() {
        context.composer.pendingFocus = false
        keepsComposerOpen = false
        searchComposer.isActive = false
        searchComposer.searchBar.resignFirstResponder()
        viewIfLoaded?.endEditing(true)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if hasPositioned, keepsBottomVisible, sendScrollTask == nil { scrollToBottom() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let systemBottomInset = max(0, table.adjustedContentInset.bottom - table.contentInset.bottom)
        var coveredBottom = view.safeAreaInsets.bottom
        let keyboardFrame = view.keyboardLayoutGuide.layoutFrame.intersection(view.bounds)
        if !keyboardFrame.isEmpty {
            coveredBottom = max(coveredBottom, view.bounds.maxY - keyboardFrame.minY)
        }
        if !composer.isHidden {
            let frame = composer.frame.intersection(view.bounds)
            if !frame.isEmpty { coveredBottom = max(coveredBottom, view.bounds.maxY - frame.minY) }
        }
        // UIKit already accounts for its toolbar. Only add actual keyboard or
        // composer overlap, never an unlaid-out toolbar or an empty keyboard rect.
        let insets = UIEdgeInsets(top: statusStack.bounds.height + 8, left: 0, bottom: max(0, coveredBottom - systemBottomInset) + 16, right: 0)
        if table.contentInset != insets { table.contentInset = insets }
        if hasPositioned, keepsBottomVisible, !isApplyingSnapshot, sendScrollTask == nil, !pendingScrollToBottom, !table.isDragging, !table.isDecelerating { alignBottom() }
    }

    private var bottomOffset: CGFloat {
        max(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
    }
    private func render() {
        let store = context.chats
        guard let chat = store.selectedChat else {
            cancelSendScroll(); snapshotRevision = UUID(); isApplyingSnapshot = false
            navigationItem.searchController = nil; titleControl.isHidden = true
            status.text = "Select a conversation"; status.isHidden = false; loading.stopAnimating()
            rows = []; rowsByID = [:]; var empty = NSDiffableDataSourceSnapshot<Int, String>(); empty.appendSections([0]); dataSource?.apply(empty, animatingDifferences: false); chatID = nil; return
        }
        let switched = chatID != chat.id
        if switched {
            cancelSendScroll()
            paginationTask?.cancel(); paginationTask = nil; chatID = chat.id; hasPositioned = false; firstUnreadID = nil; keepsBottomVisible = true
            closeComposer()
        }
        titleControl.configure(chat); titleControl.isHidden = false
        if UIDevice.current.userInterfaceIdiom == .phone {
            if navigationItem.searchController !== searchComposer { navigationItem.searchController = searchComposer }
            let input = context.composer
            if searchComposer.searchBar.text != input.draft { searchComposer.searchBar.text = input.draft }
            searchComposer.searchBar.placeholder = input.messageFieldPrompt
            searchComposer.searchBar.searchTextField.isEnabled = !input.cannotMessage && !input.isSavingEdit
        }
        let loaded = store.messagesChatID == chat.id
        if loaded && !hasPositioned { firstUnreadID = TimelineRow.firstUnreadID(store: store, chat: chat) }
        let next = TimelineRow.make(store: store, chat: chat, firstUnreadID: firstUnreadID)
        status.text = store.messagesError.map { $0 + " — Tap to retry" } ?? (store.isLoadingMessages && next.isEmpty ? "Loading messages…" : (next.isEmpty ? "No messages stored on this device" : nil))
        status.isHidden = status.text == nil
        loading.isHidden = !store.isLoadingOlderMessages
        if store.isLoadingOlderMessages { loading.startAnimating() } else { loading.stopAnimating() }
        guard next != rows || switched else { return }
        let atBottom = keepsBottomVisible || bottomOffset - table.contentOffset.y < 100
        let firstVisible = table.indexPathsForVisibleRows?.sorted().first
        let anchor = firstVisible.flatMap { rows.indices.contains($0.row) ? rows[$0.row].id : nil }
        let offset = firstVisible.map { table.contentOffset.y - table.rectForRow(at: $0).minY } ?? 0
        let previous = rowsByID
        rows = next; rowsByID = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>(); snapshot.appendSections([0]); snapshot.appendItems(next.map(\.id))
        snapshot.reconfigureItems(next.filter { previous[$0.id] != nil && previous[$0.id] != $0 }.map(\.id))
        let revision = UUID()
        snapshotRevision = revision
        isApplyingSnapshot = true
        dataSource?.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self, self.snapshotRevision == revision, self.chatID == chat.id else { return }
            defer { self.isApplyingSnapshot = false }
            self.table.layoutIfNeeded(); self.view.layoutIfNeeded()
            if self.pendingScrollToBottom {
                self.hasPositioned = loaded || self.hasPositioned
                self.scheduleSendScroll()
            } else if self.sendScrollTask != nil {
                // Snapshot/layout updates must not interrupt the send animation.
            } else if loaded && !self.hasPositioned {
                self.hasPositioned = true
                self.scrollToBottom()
            } else if atBottom {
                self.scrollToBottom()
            } else if let anchor, let index = self.dataSource?.indexPath(for: anchor) {
                let y = self.table.rectForRow(at: index).minY + offset
                self.table.setContentOffset(CGPoint(x: 0, y: max(-self.table.adjustedContentInset.top, y)), animated: false)
            }
        }

    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { cancelSendScroll() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isDragging || scrollView.isDecelerating { keepsBottomVisible = bottomOffset - scrollView.contentOffset.y < 2 }
        guard !isApplyingSnapshot, hasPositioned, scrollView.isDragging || scrollView.isDecelerating,
              scrollView.contentOffset.y + scrollView.adjustedContentInset.top < 160,
              let chatID, context.chats.hasMoreMessages(for: chatID), paginationTask == nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }; _ = await context.chats.loadOlderMessages(for: chatID); paginationTask = nil
        }
    }
    private func requestSendScroll() {
        pendingScrollToBottom = true
        keepsBottomVisible = true
        scheduleSendScroll()
    }

    private func cancelSendScroll() {
        sendScrollTask?.cancel()
        sendScrollTask = nil
        sendScrollRevision = UUID()
        pendingScrollToBottom = false
    }

    private func scheduleSendScroll() {
        sendScrollTask?.cancel()
        let revision = UUID()
        sendScrollRevision = revision
        let targetChatID = chatID
        sendScrollTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self, sendScrollRevision == revision, chatID == targetChatID else { return }
            // A snapshot completion will reschedule once self-sizing rows exist.
            guard !isApplyingSnapshot else { sendScrollTask = nil; return }
            view.layoutIfNeeded()
            table.layoutIfNeeded()
            pendingScrollToBottom = false
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25,
                           delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                self.table.contentOffset = CGPoint(x: self.table.contentOffset.x, y: self.bottomOffset)
            } completion: { [weak self] _ in
                guard let self, self.sendScrollRevision == revision else { return }
                self.sendScrollTask = nil
                self.alignBottom()
            }
        }
    }

    private func scrollToBottom() {
        guard sendScrollTask == nil, !pendingScrollToBottom else { return }
        guard !rows.isEmpty, table.numberOfSections > 0, table.numberOfRows(inSection: 0) >= rows.count else { return }
        keepsBottomVisible = true
        view.layoutIfNeeded()
        table.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0), at: .bottom, animated: false)
        table.layoutIfNeeded()
        alignBottom()
    }
    private func alignBottom() {
        let y = bottomOffset
        guard abs(table.contentOffset.y - y) > 0.5 else { return }
        table.setContentOffset(CGPoint(x: table.contentOffset.x, y: y), animated: false)
    }
    private func scrollToMessage(_ id: String) { if let row = rows.firstIndex(where: { $0.message?.id == id }) { table.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: false) } }
    private func jump(to id: String) {
        keepsBottomVisible = false
        if rows.contains(where: { $0.message?.id == id }) { scrollToMessage(id); return }
        guard let chatID else { return }
        Task { [weak self] in
            guard let self else { return }
            while context.chats.selectedChatID == chatID, context.chats.hasMoreMessages(for: chatID), !Task.isCancelled {
                guard await context.chats.loadOlderMessages(for: chatID) else { break }
                if context.chats.messages(for: chatID).contains(where: { $0.id == id }) { await Task.yield(); scrollToMessage(id); break }
            }
        }
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard rows.indices.contains(indexPath.row), let message = rows[indexPath.row].message, let chat = context.chats.selectedChat else { return nil }
        return UIContextMenuConfiguration(identifier: message.id as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let actions = ConversationActions.message(message, chat: chat, context: context)
            var sections = [UIMenu(title: "Reactions", children: ConversationActions.reactions.map { ConversationActions.reaction($0, message: message, chat: chat, store: context.chats).uiAction })]
            sections.append(UIMenu(title: message.timestampText, options: .displayInline, children: actions.filter { !$0.destructive }.map(\.uiAction)))
            let attachments = (message.attachments ?? []).map { attachment in
                UIAction(title: "Save or Share \(attachment.fileName ?? attachment.typeLabel)", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share(attachment, source: tableView.cellForRow(at: indexPath)) }
            }
            if !attachments.isEmpty { sections.append(UIMenu(options: .displayInline, children: attachments)) }
            let destructiveActions = actions.filter(\.destructive)
            if !destructiveActions.isEmpty { sections.append(UIMenu(options: .displayInline, children: destructiveActions.map(\.uiAction))) }
            return UIMenu(children: sections)
        }
    }
    @objc private func reloadMessages() { guard let chatID else { return }; Task { await context.chats.loadMessages(for: chatID) } }
    private func chooseFiles() {
        attachmentChatID = context.chats.selectedChatID
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true); picker.allowsMultipleSelection = true; picker.delegate = self; present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let target = attachmentChatID else { return }; attachmentChatID = nil
        for url in urls { context.composer.handleFileImport(.success(url), for: target) }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { attachmentChatID = nil }
    private func choosePhotos() {
        attachmentChatID = context.chats.selectedChatID
        var config = PHPickerConfiguration(photoLibrary: .shared()); config.selectionLimit = 0; config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config); picker.delegate = self; present(picker, animated: true)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let target = attachmentChatID else { return }; attachmentChatID = nil
        let token = APIClient.accessToken
        for result in results {
            let provider = result.itemProvider
            guard let type = provider.registeredTypeIdentifiers.first else { continue }
            provider.loadFileRepresentation(forTypeIdentifier: type) { [weak context] url, _ in
                guard let url, let data = try? Data(contentsOf: url) else { return }
                let name = url.lastPathComponent; let mime = UTType(type)?.preferredMIMEType ?? url.mimeType
                Task { @MainActor in guard APIClient.accessToken == token else { return }; context?.composer.addAttachment(data: data, fileName: name, mimeType: mime, to: target) }
            }
        }
    }
    private func showInfo() { guard let chat = context.chats.selectedChat else { return }; present(UINavigationController(rootViewController: MobileInfoController(chat: chat)), animated: true) }
    private func showProfile(_ person: ChatParticipant) { present(UINavigationController(rootViewController: MobileInfoController(participant: person)), animated: true) }
    private func preview(_ attachment: Attachment) {
        Task {
            do { previewURL = try await AttachmentFiles.load(attachment); let controller = QLPreviewController(); controller.dataSource = self; present(controller, animated: true) }
            catch { context.chats.messagesError = error.localizedDescription }
        }
    }
    private func share(_ attachment: Attachment, source: UIView?) {
        Task {
            do {
                let url = try await AttachmentFiles.load(attachment)
                let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                controller.popoverPresentationController?.sourceView = source ?? view
                controller.popoverPresentationController?.sourceRect = source?.bounds ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                present(controller, animated: true)
            } catch { context.chats.messagesError = error.localizedDescription }
        }
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { (previewURL ?? URL.temporaryDirectory) as NSURL }
    isolated deinit { paginationTask?.cancel(); sendScrollTask?.cancel() }
}
#endif
