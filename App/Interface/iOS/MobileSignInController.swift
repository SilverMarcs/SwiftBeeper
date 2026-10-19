#if os(iOS)
import UIKit

@MainActor
final class MobileSignInController: UIViewController, UITextFieldDelegate {
    private let context: AppContext
    private let model: BeeperSignInModel
    private let observation = ObservationLifetime()
    private let titleLabel = UILabel()
    private let help = UILabel()
    private let field = UITextField()
    private let error = UILabel()
    private let continueButton = UIButton(type: .system)
    private let back = UIButton(type: .system)
    private var shownStep: BeeperSignInStep?

    init(context: AppContext, recovery: Bool) {
        self.context = context; model = BeeperSignInModel(startsWithRecoveryKey: recovery)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        titleLabel.font = .preferredFont(forTextStyle: .title1).withTraits(.traitBold); titleLabel.textAlignment = .center; titleLabel.numberOfLines = 0
        help.textAlignment = .center; error.textAlignment = .center
        help.font = .preferredFont(forTextStyle: .body); help.textColor = .secondaryLabel; help.numberOfLines = 0
        error.font = .preferredFont(forTextStyle: .callout); error.textColor = .systemRed; error.numberOfLines = 0
        for label in [titleLabel, help, error] { label.adjustsFontForContentSizeCategory = true }
        field.borderStyle = .roundedRect; field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no; field.autocapitalizationType = .none; field.returnKeyType = .continue; field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        continueButton.configuration = .filled(); continueButton.setTitle("Continue", for: .normal)
        continueButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        back.setTitle("Use a Different Email", for: .normal); back.addAction(UIAction { [weak self] _ in self?.model.useDifferentEmail() }, for: .touchUpInside)
        let icon = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .largeTitle))); icon.tintColor = .tintColor; icon.contentMode = .scaleAspectFit
        let stack = UIStackView(vertical: [icon, titleLabel, help, field, continueButton, back, error], spacing: 8)
        stack.alignment = .center
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        let available = UILayoutGuide(); view.addLayoutGuide(available)
        NSLayoutConstraint.activate([available.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), available.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)])
        let keyboardCenter = stack.centerYAnchor.constraint(equalTo: available.centerYAnchor)
        keyboardCenter.priority = .defaultLow
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor), keyboardCenter,
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 388), stack.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 16), stack.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor), field.widthAnchor.constraint(equalTo: stack.widthAnchor), error.widthAnchor.constraint(equalTo: stack.widthAnchor), field.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
        let preferredWidth = stack.widthAnchor.constraint(equalToConstant: 388); preferredWidth.priority = .defaultHigh; preferredWidth.isActive = true
        observation.track { [weak self] in self?.render() }
    }
    private func render() {
        let step = model.step
        titleLabel.text = "Sign in to Beeper"
        help.text = SignInPresentation.help(for: step, email: model.email)
        continueButton.setTitle(model.isWorking ? model.progressMessage : SignInPresentation.button(for: step), for: .normal)
        continueButton.isEnabled = step == .email ? model.canSendCode : (step == .code ? model.canSubmitCode : model.canSubmitRecoveryKey)
        field.isEnabled = !model.isWorking
        error.text = model.errorMessage; error.isHidden = model.errorMessage == nil; back.isHidden = step != .code
        if shownStep != step {
            shownStep = step
            field.isSecureTextEntry = step == .recoveryKey
            field.keyboardType = step == .email ? .emailAddress : (step == .code ? .numberPad : .asciiCapable)
            field.textContentType = step == .email ? .emailAddress : (step == .code ? .oneTimeCode : .password)
            field.placeholder = step == .email ? "you@example.com" : (step == .code ? "123456" : "Recovery key")
            field.text = step == .email ? model.email : (step == .code ? model.code : model.recoveryKey)
            field.textAlignment = step == .code ? .center : .natural
            if step != .email { field.becomeFirstResponder() }; field.reloadInputViews()
        }
    }
    @objc private func textChanged() {
        switch model.step { case .email: model.email = field.text ?? ""; case .code: model.code = field.text ?? ""; case .recoveryKey: model.recoveryKey = field.text ?? "" }
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { submit(); return false }
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
