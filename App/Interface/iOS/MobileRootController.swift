#if os(iOS)
import UIKit

@MainActor
final class MobileRootController: UIViewController {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private var shownState: ApplicationState?

    init(context: AppContext) { self.context = context; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        observation.track { [weak self] in self?.render() }
    }
    private func render() {
        let state = context.state
        guard state != shownState else { return }; shownState = state
        for child in children { child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent() }
        let child: UIViewController
        switch state {
        case .ready: child = MobileConversationsController(context: context)
        case .signIn(let recovery): child = MobileSignInController(context: context, recovery: recovery)
        case .starting, .failed:
            let status = UIViewController(); status.view.backgroundColor = .systemBackground
            let label = UILabel(); label.numberOfLines = 0; label.textAlignment = .center
            let stack = UIStackView(vertical: [label], spacing: 16); stack.alignment = .center
            if case .failed(let error) = state {
                label.text = "Couldn’t open messages\n\n" + error
                let retry = UIButton(type: .system); retry.setTitle("Try Again", for: .normal)
                retry.addAction(UIAction { [weak context] _ in context?.start() }, for: .touchUpInside)
                stack.addArrangedSubview(retry)
            } else {
                label.text = "Opening your messages…"
                let progress = UIActivityIndicatorView(style: .medium); progress.startAnimating(); stack.addArrangedSubview(progress)
            }
            status.view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: status.view.centerXAnchor), stack.centerYAnchor.constraint(equalTo: status.view.centerYAnchor), stack.widthAnchor.constraint(lessThanOrEqualTo: status.view.widthAnchor, multiplier: 0.85)])
            child = status
        }
        addChild(child); view.addSubview(child.view); child.view.pinEdges(to: view); child.didMove(toParent: self)
    }
}
#endif
