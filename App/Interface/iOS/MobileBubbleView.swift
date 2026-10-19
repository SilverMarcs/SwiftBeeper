#if os(iOS)
import UIKit

@MainActor
final class MobileBubbleView: UIView {
    private let outgoing: Bool
    private let gradient = CAGradientLayer()
    init(outgoing: Bool, radius: CGFloat = 12) {
        self.outgoing = outgoing
        super.init(frame: .zero)
        layer.cornerRadius = radius
        if outgoing { layer.addSublayer(gradient); gradient.cornerRadius = radius }
        else { backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? .tertiarySystemBackground : .secondarySystemBackground } }
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        if outgoing { gradient.frame = bounds; gradient.colors = [tintColor.withAlphaComponent(0.85).cgColor, tintColor.cgColor] }
    }
}
#endif
