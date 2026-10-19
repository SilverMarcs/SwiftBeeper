#if os(macOS)
import AppKit
import PhotosUI
import UniformTypeIdentifiers

@MainActor
final class MacConversationController: NSViewController, NSTableViewDelegate, NSMenuDelegate, PHPickerViewControllerDelegate {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let stateLabel = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private lazy var composer = MacComposerView(context: context)
    private lazy var statusStack = NSStackView(vertical: [stateLabel, progress], spacing: 4)
    private(set) lazy var composerAccessory: NSSplitViewItemAccessoryViewController = {
        let accessory = NSSplitViewItemAccessoryViewController()
        accessory.automaticallyAppliesContentInsets = false
        accessory.preferredScrollEdgeEffectStyle = .soft
        accessory.view = composer
        return accessory
    }()
    private var dataSource: NSTableViewDiffableDataSource<Int, String>?
    private var rows: [TimelineRow] = []
    private var rowsByID: [String: TimelineRow] = [:]
    private var chatID: String?
    private var firstUnreadID: String?
    private var hasPositioned = false
    private var paginationTask: Task<Void, Never>?
    private var scrollObserver: NSObjectProtocol?
    private var tableFrameObserver: NSObjectProtocol?
    private var attachmentChatID: String?
    private var infoWindow: NSWindow?
    private var pendingScrollToBottom = false
    private var isApplyingSnapshot = false
    private var snapshotRevision = UUID()
    private var isUpdatingLayout = false
    private var previousOriginY: CGFloat = 0
    private var keepsBottomVisible = true

    init(context: AppContext) { self.context = context; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = NSView() }
    override func viewDidLoad() {
        super.viewDidLoad()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message")); table.addTableColumn(column)
        table.headerView = nil; table.usesAutomaticRowHeights = true; table.rowHeight = 70
        table.style = .plain; table.headerView = nil
        table.intercellSpacing = .zero; table.selectionHighlightStyle = .none; table.delegate = self
        table.backgroundColor = .windowBackgroundColor
        let menu = NSMenu(); menu.delegate = self; table.menu = menu
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        stateLabel.alignment = .center; stateLabel.textColor = .secondaryLabelColor
        progress.style = .spinning; progress.controlSize = .small
        composer.onChoosePhotos = { [weak self] in self?.choosePhotos() }
        composer.onSubmit = { [weak self] in self?.pendingScrollToBottom = true; self?.scrollToBottom() }
        view.addSubview(scroll); scroll.pinEdges(to: view)
        statusStack.alignment = .centerX
        view.addSubview(statusStack); statusStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            statusStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            statusStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        ])
        dataSource = NSTableViewDiffableDataSource<Int, String>(tableView: table) { [weak self] table, _, _, id in
            guard let self, let row = rowsByID[id], let chat = context.chats.selectedChat else { return NSView() }
            let cell = (table.makeView(withIdentifier: NSUserInterfaceItemIdentifier("message"), owner: nil) as? MacMessageRowView) ?? MacMessageRowView()
            cell.identifier = NSUserInterfaceItemIdentifier("message")
            cell.configure(row, chat: chat, context: context)
            cell.onJump = { [weak self] id in self?.jump(to: id) }
            cell.onProfile = { [weak self] participant in self?.showProfile(participant) }
            cell.onPreview = { [weak self] attachment in self?.preview(attachment) }
            return cell
        }
        scrollObserver = NotificationCenter.default.addObserver(forName: NSScrollView.didLiveScrollNotification, object: scroll, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollChanged() }
        }
        table.postsFrameChangedNotifications = true
        tableFrameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: table, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.hasPositioned, self.keepsBottomVisible, !self.isApplyingSnapshot, !self.isUpdatingLayout else { return }
                self.alignBottom()
            }
        }
        observation.track { [weak self] in self?.render() }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if context.chats.selectedChatID != nil { context.composer.pendingFocus = true }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let wasUpdatingLayout = isUpdatingLayout
        isUpdatingLayout = true
        defer { isUpdatingLayout = wasUpdatingLayout }
        // Keep the viewport behind the bars; only the resting content is inset.
        let safeArea = view.safeAreaInsets
        let insets = NSEdgeInsets(top: safeArea.top + statusStack.bounds.height + 8, left: safeArea.left, bottom: safeArea.bottom + 16, right: safeArea.right)
        if scroll.contentInsets.top != insets.top || scroll.contentInsets.bottom != insets.bottom || scroll.contentInsets.left != insets.left || scroll.contentInsets.right != insets.right {
            scroll.contentInsets = insets
            scroll.scrollerInsets = insets
        }
        if hasPositioned, keepsBottomVisible, !isApplyingSnapshot { alignBottom() }
    }

    private var bottomOffset: CGFloat {
        let clip = scroll.contentView
        var bounds = clip.bounds
        bounds.origin.y = clip.documentRect.maxY + clip.contentInsets.bottom
        return clip.constrainBoundsRect(bounds).minY
    }

    private func render() {
        isUpdatingLayout = true
        defer { isUpdatingLayout = false }
        let store = context.chats
        guard let chat = store.selectedChat else {
            snapshotRevision = UUID(); isApplyingSnapshot = false
            stateLabel.stringValue = "Select a conversation"; stateLabel.isHidden = false
            composerAccessory.isHidden = true; progress.isHidden = true
            if !rows.isEmpty { rows = []; rowsByID = [:]; var empty = NSDiffableDataSourceSnapshot<Int, String>(); empty.appendSections([0]); dataSource?.apply(empty, animatingDifferences: false) }
            chatID = nil; return
        }
        let switched = chatID != chat.id
        if switched {
            paginationTask?.cancel(); paginationTask = nil; chatID = chat.id
            hasPositioned = false; firstUnreadID = nil; keepsBottomVisible = true
            if view.window != nil { context.composer.pendingFocus = true }
        }
        composerAccessory.isHidden = false
        progress.isHidden = !store.isLoadingOlderMessages
        if store.isLoadingOlderMessages { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        let loaded = store.messagesChatID == chat.id
        if loaded && !hasPositioned {
            firstUnreadID = TimelineRow.firstUnreadID(store: store, chat: chat)
        }
        let next = TimelineRow.make(store: store, chat: chat, firstUnreadID: firstUnreadID)
        stateLabel.stringValue = store.messagesError ?? (store.isLoadingMessages && next.isEmpty ? "Loading messages…" : (next.isEmpty ? "No messages stored on this device" : ""))
        stateLabel.isHidden = stateLabel.stringValue.isEmpty
        guard next != rows || switched else { return }
        let atBottom = keepsBottomVisible || bottomOffset - scroll.contentView.bounds.minY < 100
        let visible = table.rows(in: scroll.contentView.bounds)
        let anchor = visible.location != NSNotFound && rows.indices.contains(visible.location) ? rows[visible.location].id : nil
        let offset = visible.location != NSNotFound && rows.indices.contains(visible.location) ? scroll.contentView.bounds.minY - table.rect(ofRow: visible.location).minY : 0
        let previousRows = rowsByID
        rows = next; rowsByID = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>(); snapshot.appendSections([0]); snapshot.appendItems(next.map(\.id))
        snapshot.reloadItems(next.filter { previousRows[$0.id] != nil && previousRows[$0.id] != $0 }.map(\.id))
        let revision = UUID()
        snapshotRevision = revision
        isApplyingSnapshot = true
        dataSource?.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self, self.snapshotRevision == revision, self.chatID == chat.id else { return }
            defer { self.isApplyingSnapshot = false }
            self.table.layoutSubtreeIfNeeded(); self.view.layoutSubtreeIfNeeded()
            if loaded && !self.hasPositioned {
                self.hasPositioned = true
                self.scrollToBottom()
            } else if self.pendingScrollToBottom || atBottom {
                self.pendingScrollToBottom = false; self.scrollToBottom()
            } else if let anchor, let index = self.rows.firstIndex(where: { $0.id == anchor }) {
                self.scroll.contentView.scroll(to: NSPoint(x: 0, y: self.table.rect(ofRow: index).minY + offset)); self.scroll.reflectScrolledClipView(self.scroll.contentView)
            }
        }

    }

    private func scrollChanged() {
        let origin = scroll.contentView.bounds.minY
        let movedUp = origin < previousOriginY
        previousOriginY = origin
        if !isUpdatingLayout, !isApplyingSnapshot { keepsBottomVisible = bottomOffset - origin < 2 }
        guard !isUpdatingLayout, !isApplyingSnapshot, movedUp, hasPositioned, origin < 160, let chatID, context.chats.hasMoreMessages(for: chatID), paginationTask == nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            _ = await context.chats.loadOlderMessages(for: chatID)
            paginationTask = nil
        }
    }
    private func scrollToBottom() {
        guard !rows.isEmpty else { return }
        keepsBottomVisible = true
        view.layoutSubtreeIfNeeded()
        table.scrollRowToVisible(rows.count - 1)
        table.layoutSubtreeIfNeeded()
        alignBottom()
    }
    private func alignBottom() {
        let y = bottomOffset
        previousOriginY = y
        guard abs(scroll.contentView.bounds.minY - y) > 0.5 else { return }
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func jump(to id: String) {
        keepsBottomVisible = false
        if let index = rows.firstIndex(where: { $0.message?.id == id }) { table.scrollRowToVisible(index); return }
        guard let chatID else { return }
        Task { [weak self] in
            guard let self else { return }
            while context.chats.selectedChatID == chatID, context.chats.hasMoreMessages(for: chatID), !Task.isCancelled {
                guard await context.chats.loadOlderMessages(for: chatID) else { break }
                if let index = rows.firstIndex(where: { $0.message?.id == id }) { table.scrollRowToVisible(index); break }
            }
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard rows.indices.contains(table.clickedRow), let message = rows[table.clickedRow].message, let chat = context.chats.selectedChat else { return }
        menu.addItem(.sectionHeader(title: message.timestampText))
        let reactions = NSMenu(title: "Reactions")
        for key in ConversationActions.reactions { reactions.addItem(MacActionMenuItem(ConversationActions.reaction(key, message: message, chat: chat, store: context.chats))) }
        let item = NSMenuItem(title: "Reactions", action: nil, keyEquivalent: ""); item.submenu = reactions; menu.addItem(item)
        menu.addItem(.separator())
        let actions = ConversationActions.message(message, chat: chat, context: context)
        for action in actions where !action.destructive { menu.addItem(MacActionMenuItem(action)) }
        let attachments = message.attachments ?? []
        if !attachments.isEmpty { menu.addItem(.separator()) }
        for attachment in attachments {
            menu.addItem(MacActionMenuItem(RelayAction(title: "Save \(attachment.fileName ?? attachment.typeLabel)…", symbol: "arrow.down") { [weak self] in self?.save(attachment) }))
        }
        let destructiveActions = actions.filter(\.destructive)
        if !destructiveActions.isEmpty { menu.addItem(.separator()) }
        for action in destructiveActions { menu.addItem(MacActionMenuItem(action)) }
    }
    func showInfo() {
        guard let chat = context.chats.selectedChat else { return }
        showPanel(MacInfoController(chat: chat, onProfile: { [weak self] in self?.showProfile($0) }), title: "Chat Info")
    }
    func showProfile(_ participant: ChatParticipant) { showPanel(MacInfoController(participant: participant), title: "Profile") }
    private func showPanel(_ controller: MacInfoController, title: String) {
        guard let parent = infoWindow.flatMap({ $0.sheetParent != nil ? $0 : nil }) ?? view.window else { return }
        let window = NSWindow(contentViewController: controller); window.title = title
        window.styleMask = [.titled, .resizable]; window.setContentSize(NSSize(width: 430, height: 520))
        window.isReleasedWhenClosed = false
        controller.onClose = { [weak window, weak parent] in if let window { parent?.endSheet(window); window.orderOut(nil) } }
        infoWindow = window; parent.beginSheet(window)
    }

    private func choosePhotos() {
        attachmentChatID = context.chats.selectedChatID
        var configuration = PHPickerConfiguration(photoLibrary: .shared()); configuration.selectionLimit = 0; configuration.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = self
        presentAsSheet(picker)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(picker)
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
    private func preview(_ attachment: Attachment) {
        MacPreviewPresenter.shared.show(attachment) { [weak self] error in self?.context.chats.messagesError = error.localizedDescription }
    }
    private func save(_ attachment: Attachment) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = attachment.fileName ?? "Attachment"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                do {
                    let source = try await AttachmentFiles.load(attachment)
                    let data = try Data(contentsOf: source); try data.write(to: destination, options: .atomic)
                } catch { self?.context.chats.messagesError = error.localizedDescription }
            }
        }
    }
    isolated deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        if let tableFrameObserver { NotificationCenter.default.removeObserver(tableFrameObserver) }
        paginationTask?.cancel()
    }
}
#endif
