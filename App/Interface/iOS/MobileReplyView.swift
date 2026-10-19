#if os(iOS)
import UIKit

@MainActor
final class MobileReplyView: UIControl {
    init(message: Message, onOpen: @escaping () -> Void) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemFill; layer.cornerRadius = 8
        let rule = UIView(); rule.backgroundColor = .tintColor; rule.layer.cornerRadius = 1.5
        let sender = UILabel(); sender.text = message.senderDisplayName; sender.font = .preferredFont(forTextStyle: .caption1).withTraits(.traitBold); sender.textColor = .secondaryLabel
        let quote = UILabel(); quote.text = message.displayText; quote.font = .preferredFont(forTextStyle: .caption1); quote.textColor = .secondaryLabel; quote.numberOfLines = 1
        let labels = UIStackView(vertical: [sender, quote], spacing: 2)
        let row = UIStackView(arrangedSubviews: [rule, labels]); row.spacing = 6; row.isUserInteractionEnabled = false
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), row.topAnchor.constraint(equalTo: topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), rule.widthAnchor.constraint(equalToConstant: 3)])
        addAction(UIAction { _ in onOpen() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { nil }
}
#endif
