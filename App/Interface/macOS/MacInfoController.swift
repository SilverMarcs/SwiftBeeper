#if os(macOS)
import AppKit

@MainActor
final class MacInfoController: NSViewController, NSToolbarDelegate {
    var onClose: (() -> Void)?
    private var chat: Chat?
    private let participant: ChatParticipant?
    private let onProfile: ((ChatParticipant) -> Void)?
    private let stack = NSStackView(vertical: [], spacing: 20)
    private var detailTask: Task<Void, Never>?

    init(chat: Chat, onProfile: @escaping (ChatParticipant) -> Void) {
        self.chat = chat; participant = nil; self.onProfile = onProfile
        super.init(nibName: nil, bundle: nil)
    }
    init(participant: ChatParticipant) {
        self.participant = participant; chat = nil; onProfile = nil
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = NSView() }
    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let document = MacFlippedView(); scroll.documentView = document
        view.addSubview(scroll); scroll.pinEdges(to: view)
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)])
        render()
        if let chat, chat.participants?.hasMore == true {
            detailTask = Task { [weak self] in
                guard let detail = try? await APIClient.getChat(chatID: chat.id, maxParticipantCount: 15), !Task.isCancelled else { return }
                self?.chat = detail; self?.render()
            }
        }
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        let toolbar = NSToolbar(identifier: "RelayInfo"); toolbar.delegate = self; toolbar.displayMode = .iconOnly
        view.window?.toolbarStyle = .unified; view.window?.toolbar = toolbar
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("close")] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier.rawValue == "close" else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier); item.label = "Close"; item.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil); item.target = self; item.action = #selector(closeSheet)
        return item
    }
    @objc private func closeSheet() { onClose?() }
    override func cancelOperation(_ sender: Any?) { onClose?() }

    private func render() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if let participant {
            let avatar = MacAvatarView(size: 96); avatar.configure(name: participant.displayName, source: participant.imgURL)
            if let source = participant.imgURL { avatar.onOpen = { MacPreviewPresenter.shared.showImage(source) } }
            let name = NSTextField(labelWithString: participant.displayName); name.font = .systemFont(ofSize: 15, weight: .semibold)
            let heading = NSStackView(vertical: [avatar, name], spacing: 12); heading.alignment = .centerX
            if let username = participant.username, !username.isEmpty, username != participant.displayName {
                let username = NSTextField(labelWithString: username); username.font = .preferredFont(forTextStyle: .subheadline); username.textColor = .secondaryLabelColor; heading.addArrangedSubview(username)
            }
            stack.addArrangedSubview(heading); heading.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            var rows = [field("Name", participant.displayName)]
            if let username = participant.username, !username.isEmpty { rows.append(field("Username", username)) }
            if participant.isSelf == true { rows.append(field("Account", "You")) }
            if participant.cannotMessage == true { rows.append(field("Messaging", "Unavailable")) }
            section("Profile", rows: rows)
            section("Identifiers", rows: [field("Participant ID", participant.id, monospaced: true)])
        }
        if let chat {
            var general = [field("Type", chat.isGroupChat ? "Group" : "Direct Message")]
            if let accountID = chat.accountID { general.append(field("Account", accountID)) }
            section("General", rows: general)
            if let participants = chat.participants {
                let count = participants.total ?? participants.items.count
                var people: [NSView] = participants.items.prefix(15).map { person in MacParticipantRowView(person) { [weak self] in self?.onProfile?(person) } }
                let remaining = max(0, count - min(15, participants.items.count))
                if remaining > 0 { let more = NSTextField(labelWithString: "\(remaining) more members"); more.textColor = .secondaryLabelColor; people.append(more) }
                section("Participants (\(count))", rows: people)
            }
            section("Identifiers", rows: [field("Chat ID", chat.id, monospaced: true)])
        }
    }
    private func section(_ title: String, rows: [NSView]) {
        let heading = NSTextField(labelWithString: title); heading.font = .preferredFont(forTextStyle: .headline)
        let content = NSStackView(vertical: [], spacing: 10)
        for (index, row) in rows.enumerated() {
            if index > 0 { let line = NSBox(); line.boxType = .separator; content.addArrangedSubview(line); line.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
            content.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        let group = MacFormGroupView(); group.addSubview(content); content.pinEdges(to: group, inset: 10)
        let section = NSStackView(vertical: [heading, group], spacing: 6)
        stack.addArrangedSubview(section); section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; group.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
    }
    private func field(_ title: String, _ value: String, monospaced: Bool = false) -> NSView {
        let heading = NSTextField(labelWithString: title)
        let text = NSTextField(wrappingLabelWithString: value); text.isSelectable = true; text.textColor = .secondaryLabelColor; text.alignment = .right
        text.font = monospaced ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .preferredFont(forTextStyle: .body)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [heading, NSView(), text]); row.spacing = 8; row.alignment = .firstBaseline
        return row
    }
    isolated deinit { detailTask?.cancel() }
}
#endif
