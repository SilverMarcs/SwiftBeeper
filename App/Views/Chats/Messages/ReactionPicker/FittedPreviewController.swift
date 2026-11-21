#if os(iOS)
import UIKit

/// Shows a copy of a message scaled to fit whatever size UIKit gives the
/// preview, held against the edge its bubble sits on.
final class FittedPreviewController: UIViewController {
    private let content: UIView
    private let size: CGSize
    private let isOutgoing: Bool

    init(content: UIView, size: CGSize, preferredSize: CGSize, isOutgoing: Bool) {
        self.content = content
        self.size = size
        self.isOutgoing = isOutgoing
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = preferredSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        content.bounds = CGRect(origin: .zero, size: size)
        view.addSubview(content)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let scale = min(bounds.width / size.width, bounds.height / size.height, 1)
        let width = size.width * scale
        let isRightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let onRight = isOutgoing != isRightToLeft
        content.transform = CGAffineTransform(scaleX: scale, y: scale)
        content.center = CGPoint(
            x: onRight ? bounds.maxX - width / 2 : bounds.minX + width / 2,
            y: bounds.midY
        )
    }
}
#endif
