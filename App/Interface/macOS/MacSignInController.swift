#if os(macOS)
import AppKit

@MainActor
final class MacSignInController: NSViewController, NSTextFieldDelegate {
    private let context: AppContext
    private let model: BeeperSignInModel
    private let observation = ObservationLifetime()
    private let titleLabel = NSTextField(labelWithString: "")
    private let help = NSTextField(wrappingLabelWithString: "")
    private let field = NSTextField()
    private let recovery = NSSecureTextField()
    private let error = NSTextField(wrappingLabelWithString: "")
    private lazy var next = MacActionButton("Continue") { [weak self] in self?.submit() }
    private lazy var back = MacActionButton("Use a Different Email") { [weak self] in self?.model.useDifferentEmail() }
    private var shownStep: BeeperSignInStep?

    init(context: AppContext, recovery: Bool) {
        self.context = context
        model = BeeperSignInModel(startsWithRecoveryKey: recovery)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = NSView() }
    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        let icon = NSImageView(image: NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .controlAccentColor; icon.symbolConfiguration = .init(pointSize: 26, weight: .regular)
        help.alignment = .center; error.alignment = .center
        next.controlSize = .large; next.bezelColor = .controlAccentColor
        back.isBordered = false
        help.textColor = .secondaryLabelColor
        error.textColor = .systemRed
        field.delegate = self; recovery.delegate = self
        field.target = self; field.action = #selector(continueAction)
        recovery.target = self; recovery.action = #selector(continueAction)
        next.keyEquivalent = "\r"
        let stack = NSStackView(vertical: [icon, titleLabel, help, field, recovery, next, back, error], spacing: 8)
        stack.alignment = .centerX
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: view.centerXAnchor), stack.centerYAnchor.constraint(equalTo: view.centerYAnchor), stack.widthAnchor.constraint(equalToConstant: 388)])
        for child in [help, field, recovery, error] { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        observation.track { [weak self] in self?.render() }
    }

    private func render() {
        let step = model.step
        titleLabel.stringValue = "Sign in to Beeper"
        help.stringValue = SignInPresentation.help(for: step, email: model.email)
        field.placeholderString = step == .email ? "you@example.com" : "123456"
        field.alignment = step == .code ? .center : .left
        field.font = step == .code ? .monospacedDigitSystemFont(ofSize: 15, weight: .regular) : .preferredFont(forTextStyle: .body)
        recovery.placeholderString = "Recovery key"
        field.isHidden = step == .recoveryKey; recovery.isHidden = step != .recoveryKey
        back.isHidden = step != .code
        next.title = model.isWorking ? model.progressMessage : SignInPresentation.button(for: step)
        next.isEnabled = step == .email ? model.canSendCode : (step == .code ? model.canSubmitCode : model.canSubmitRecoveryKey)
        field.isEnabled = !model.isWorking; recovery.isEnabled = !model.isWorking
        error.stringValue = model.errorMessage ?? ""; error.isHidden = error.stringValue.isEmpty
        if shownStep != step {
            shownStep = step; field.stringValue = step == .email ? model.email : model.code
            view.window?.makeFirstResponder(step == .recoveryKey ? recovery : field)
        }
    }
    func controlTextDidChange(_ notification: Notification) {
        if model.step == .email { model.email = field.stringValue }
        else if model.step == .code { model.code = field.stringValue }
        else { model.recoveryKey = recovery.stringValue }
    }
    @objc private func continueAction() { submit() }
    private func submit() {
        Task {
            switch model.step {
            case .email: guard model.canSendCode else { return }; await model.sendCode()
            case .code: guard model.canSubmitCode else { return }; await model.submitCode(sessionStore: context.session)
            case .recoveryKey: guard model.canSubmitRecoveryKey else { return }; await model.submitRecoveryKey(sessionStore: context.session)
            }
        }
    }
}
#endif
