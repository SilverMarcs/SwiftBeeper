#if os(iOS)
import UIKit
import UserNotifications

@MainActor
final class MobileSettingsController: UITableViewController {
    private let model: SettingsModel
    private let observation = ObservationLifetime()
    private var activeObserver: NSObjectProtocol?

    init(context: AppContext) { model = SettingsModel(context: context); super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        observation.track { [weak self] in self?.render() }
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.model.refresh() } }
        Task { await model.refresh() }
    }
    private func render() {
        _ = model.context.session.accessToken
        _ = model.context.chats.currentUserProfile
        _ = model.notificationStatus
        _ = model.context.notifications.authorizationStatus
        _ = model.context.notifications.errorMessage
        _ = model.isSigningOut; _ = model.autoplay; _ = model.muteOnPlay
        tableView.reloadData()
        if let error = model.error, presentedViewController == nil {
            let alert = UIAlertController(title: "Settings", message: error, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak model] _ in model?.error = nil }); present(alert, animated: true)
        }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 || section == 2 ? 2 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["Account", "Notifications", "Playback", "Cache"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 1 ? model.context.notifications.errorMessage : nil }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        var config = cell.defaultContentConfiguration()
        switch indexPath.section {
        case 0:
            if indexPath.row == 0 {
                config.text = model.context.session.accessToken.isEmpty ? "Not signed in" : (model.context.chats.currentUserProfile?.displayName ?? "Beeper Account")
                config.secondaryText = model.context.chats.currentUserProfile?.username
            } else { config.text = model.isSigningOut ? "Signing Out…" : "Sign Out"; config.textProperties.color = .systemRed; cell.isUserInteractionEnabled = !model.context.session.accessToken.isEmpty && !model.isSigningOut }
        case 1:
            config.text = model.notificationStatus
            config.secondaryText = model.context.notifications.authorizationStatus == .denied ? "Open Settings" : "Reconnect"
            cell.accessoryType = .disclosureIndicator
        case 2:
            config.text = indexPath.row == 0 ? "Autoplay Videos" : "Mute on Play"
            let toggle = UISwitch(); toggle.isOn = indexPath.row == 0 ? model.autoplay : model.muteOnPlay
            toggle.addAction(UIAction { [weak model] _ in if indexPath.row == 0 { model?.autoplay = toggle.isOn } else { model?.muteOnPlay = toggle.isOn } }, for: .valueChanged)
            cell.accessoryView = toggle; cell.selectionStyle = .none
        default: config.text = "Delete File Cache"; config.image = UIImage(systemName: "trash")
        }
        cell.contentConfiguration = config; return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0 where indexPath.row == 1:
            Task { await model.signOut(); if model.context.session.accessToken.isEmpty { dismiss(animated: true) } }
        case 1:
            if model.context.notifications.authorizationStatus == .denied {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            } else { Task { await model.reconnect() } }
        case 3: model.clearCache()
        default: break
        }
    }
    isolated deinit { if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) } }
}
#endif
