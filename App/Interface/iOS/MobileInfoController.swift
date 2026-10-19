#if os(iOS)
import UIKit
import QuickLook

@MainActor
final class MobileInfoController: UITableViewController, QLPreviewControllerDataSource {
    private var previewURL: URL?
    private var chat: Chat?
    private let participant: ChatParticipant?
    private var fields: [(String, String)] = []
    private var people: [ChatParticipant] = []
    private var detailTask: Task<Void, Never>?

    init(chat: Chat) { self.chat = chat; participant = nil; super.init(style: .insetGrouped) }
    init(participant: ChatParticipant) { self.participant = participant; chat = nil; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad(); title = participant == nil ? "Chat Info" : "Profile"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        tableView.register(MobileParticipantCell.self, forCellReuseIdentifier: "participant")
        if let participant {
            let header = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            let avatar = MobileAvatarView(size: 96); avatar.configure(name: participant.displayName, source: participant.imgURL)
            avatar.onOpen = { [weak self] in self?.previewAvatar() }
            let name = UILabel(); name.text = participant.displayName; name.font = .preferredFont(forTextStyle: .title3).withTraits(.traitBold)
            let heading = UIStackView(vertical: [avatar, name], spacing: 12); heading.alignment = .center
            if let username = participant.username, !username.isEmpty, username != participant.displayName {
                let detail = UILabel(); detail.text = username; detail.font = .preferredFont(forTextStyle: .subheadline); detail.textColor = .secondaryLabel; heading.addArrangedSubview(detail)
            }
            header.addSubview(heading); heading.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([heading.centerXAnchor.constraint(equalTo: header.centerXAnchor), heading.centerYAnchor.constraint(equalTo: header.centerYAnchor)])
            tableView.tableHeaderView = header
        }
        configure()
        if let chat, chat.participants?.hasMore == true {
            detailTask = Task { [weak self] in
                do {
                    let detail = try await APIClient.getChat(chatID: chat.id, maxParticipantCount: 15)
                    guard !Task.isCancelled else { return }; self?.chat = detail; self?.configure()
                } catch { self?.fields.append(("Couldn’t load participants", error.localizedDescription)); self?.tableView.reloadData() }
            }
        }
    }
    private func configure() {
        fields = []; people = []
        if let participant {
            fields.append(("Name", participant.displayName))
            if let name = participant.username { fields.append(("Username", name)) }
            if participant.isSelf == true { fields.append(("Account", "You")) }
            if participant.cannotMessage == true { fields.append(("Messaging", "Unavailable")) }
        }
        if let chat {
            fields.append(("Type", chat.isGroupChat ? "Group" : "Direct Message"))
            if let id = chat.accountID { fields.append(("Account", id)) }
            people = Array((chat.participants?.items ?? []).prefix(15))
        }
        tableView.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { participant == nil ? 3 : 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return fields.count }
        if participant == nil && section == 1 { return people.count }
        return 1
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return participant == nil ? "General" : "Profile" }
        if participant == nil && section == 1 { return "Participants (\(chat?.participants?.total ?? people.count))" }
        return "Identifiers"
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let remaining = (chat?.participants?.total ?? people.count) - people.count
        return participant == nil && section == 1 && remaining > 0 ? "\(remaining) more members" : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if participant == nil && indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "participant", for: indexPath)
            (cell as? MobileParticipantCell)?.configure(people[indexPath.row]); return cell
        }
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let field = indexPath.section == 0 ? fields[indexPath.row] : (participant == nil ? "Chat ID" : "Participant ID", participant?.id ?? chat?.id ?? "")
        cell.textLabel?.text = field.0; cell.detailTextLabel?.text = field.1; cell.detailTextLabel?.textColor = .secondaryLabel
        if indexPath.section > 0 { cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular) }
        cell.selectionStyle = .none
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if participant == nil && indexPath.section == 1 {
            present(UINavigationController(rootViewController: MobileInfoController(participant: people[indexPath.row])), animated: true)
        } else {
            let field = indexPath.section == 0 ? fields[indexPath.row] : (participant == nil ? "Chat ID" : "Participant ID", participant?.id ?? chat?.id ?? "")
            let sheet = UIAlertController(title: field.0, message: field.1, preferredStyle: .alert)
            sheet.addAction(UIAlertAction(title: "Copy", style: .default) { _ in UIPasteboard.general.string = field.1 }); sheet.addAction(UIAlertAction(title: "Done", style: .cancel)); present(sheet, animated: true)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    private func previewAvatar() {
        guard let source = participant?.imgURL ?? chat?.imgURL else { return }
        Task {
            guard let file = await AuthenticatedImageLoader.downloadToTempFile(urlString: source, fileExtension: "jpg") else { return }
            previewURL = file
            let controller = QLPreviewController(); controller.dataSource = self; present(controller, animated: true)
        }
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { (previewURL ?? URL.temporaryDirectory) as NSURL }
    isolated deinit { detailTask?.cancel() }
}
#endif
