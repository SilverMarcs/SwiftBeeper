#if os(macOS)
import AppKit

@MainActor
final class MacRootController: NSViewController {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private var shownState: ApplicationState?

    init(context: AppContext) { self.context = context; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = NSView() }
    override func viewDidLoad() {
        super.viewDidLoad()
        observation.track { [weak self] in self?.render() }
    }

    private func render() {
        let state = context.state
        guard state != shownState else { return }
        shownState = state
        for child in children { child.view.removeFromSuperview(); child.removeFromParent() }
        switch state {
        case .ready:
            break
        case .signIn(let recovery):
            show(MacSignInController(context: context, recovery: recovery))
        case .starting, .failed:
            let controller = NSViewController()
            controller.view = NSView()
            let label = NSTextField(wrappingLabelWithString: "Opening your messages…")
            label.alignment = .center
            let stack = NSStackView(vertical: [label])
            stack.alignment = .centerX
            if case .failed(let error) = state {
                label.stringValue = "Couldn’t open messages\n\n" + error
                stack.addArrangedSubview(MacActionButton("Try Again") { [weak context] in context?.start() })
            } else {
                let progress = NSProgressIndicator(); progress.style = .spinning; progress.startAnimation(nil)
                stack.addArrangedSubview(progress)
            }
            controller.view.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor), stack.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor), stack.widthAnchor.constraint(lessThanOrEqualToConstant: 460)])
            show(controller)
        }
    }

    private func show(_ child: NSViewController) {
        addChild(child); view.addSubview(child.view); child.view.pinEdges(to: view)
    }
}
#endif
