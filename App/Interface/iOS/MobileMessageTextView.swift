#if os(iOS)
import UIKit

/// A selectable native message whose intrinsic size wraps at the conversation
/// width, including during rotation and Dynamic Type changes.
@MainActor
final class MobileMessageTextView: UITextView {
    var outgoing = false
    private let gradient = CAGradientLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = min(22, bounds.height / 2, bounds.width / 2)
        layer.cornerRadius = radius
        if outgoing {
            if gradient.superlayer == nil { layer.insertSublayer(gradient, at: 0) }
            gradient.frame = bounds; gradient.cornerRadius = radius
            gradient.colors = [tintColor.resolvedColor(with: traitCollection).withAlphaComponent(0.85).cgColor, tintColor.resolvedColor(with: traitCollection).cgColor]
        } else { gradient.removeFromSuperlayer() }
    }

    var maximumWidth: CGFloat = 300 {
        didSet { if oldValue != maximumWidth { invalidateIntrinsicContentSize() } }
    }
    override var intrinsicContentSize: CGSize {
        let inset = textContainerInset.left + textContainerInset.right + textContainer.lineFragmentPadding * 2
        let rect = attributedText.boundingRect(with: CGSize(width: max(1, maximumWidth - inset), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return CGSize(width: min(maximumWidth, ceil(rect.width) + inset), height: ceil(rect.height) + textContainerInset.top + textContainerInset.bottom)
    }
}
#endif
