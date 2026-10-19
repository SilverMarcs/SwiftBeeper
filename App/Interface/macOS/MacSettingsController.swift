#if os(macOS)
import AppKit
import UserNotifications

@MainActor
final class MacSettingsController: NSViewController {
    private let model: SettingsModel
    private let observation = ObservationLifetime()
    private let account = NSTextField(labelWithString: "")
    private let notifications = NSTextField(labelWithString: "")
    private let error = NSTextField(wrappingLabelWithString: "")
    private lazy var signOut = MacActionButton("Sign Out") { [weak self] in Task { await self?.model.signOut() } }
    private lazy var reconnect = MacActionButton("Allow Notifications") { [weak self] in self?.configureNotifications() }
    private var activeObserver: NSObjectProtocol?

    init(context: AppContext) { model = SettingsModel(context: context); super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = NSView() }
    override func viewDidLoad() {
        super.viewDidLoad()
        account.font = .preferredFont(forTextStyle: .headline)
        let autoplay = NSButton(checkboxWithTitle: "Autoplay Videos", target: self, action: #selector(toggleAutoplay(_:))); autoplay.state = model.autoplay ? .on : .off
        let mute = NSButton(checkboxWithTitle: "Mute on Play", target: self, action: #selector(toggleMute(_:))); mute.state = model.muteOnPlay ? .on : .off
        let clear = MacActionButton("Delete File Cache") { [weak self] in self?.model.clearCache() }
        let notificationRow = NSStackView(views: [notifications, reconnect]); notificationRow.spacing = 16
        error.textColor = .systemRed
        let stack = NSStackView(vertical: [heading("Account"), account, signOut, heading("Notifications"), notificationRow, heading("Playback"), autoplay, mute, heading("Cache"), clear, error], spacing: 12)
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24), stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24)])
        observation.track { [weak self] in self?.render() }
        Task { await model.refresh() }
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.model.refresh() } }
    }
    private func render() {
        let context = model.context
        account.stringValue = context.session.accessToken.isEmpty ? "Not signed in" : (context.chats.currentUserProfile?.displayName ?? "Beeper Account")
        notifications.stringValue = model.notificationStatus
        let denied = context.notifications.authorizationStatus == .denied
        reconnect.title = denied ? "Open System Settings" : (context.notifications.authorizationStatus == .notDetermined ? "Allow" : "Reconnect")
        reconnect.isEnabled = !context.session.accessToken.isEmpty && !context.notifications.isRegistering && !context.notifications.isPreparing
        signOut.isEnabled = !context.session.accessToken.isEmpty && !model.isSigningOut
        error.stringValue = model.error ?? context.notifications.errorMessage ?? ""; error.isHidden = error.stringValue.isEmpty
    }
    private func heading(_ text: String) -> NSTextField { let label = NSTextField(labelWithString: text); label.font = .preferredFont(forTextStyle: .headline); return label }
    private func configureNotifications() {
        if model.context.notifications.authorizationStatus == .denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        } else { Task { await model.reconnect() } }
    }
    @objc private func toggleAutoplay(_ sender: NSButton) { model.autoplay = sender.state == .on }
    @objc private func toggleMute(_ sender: NSButton) { model.muteOnPlay = sender.state == .on }
    isolated deinit { if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) } }
}
#endif
