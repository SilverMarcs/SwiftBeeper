#if os(iOS)
import UIKit

@MainActor
final class MobileConversationHeaderView: UIControl {
    private let avatar = MobileAvatarView(size: 28)
    private let name = UILabel()
    private let maximumNameWidth: CGFloat = 180
    private let horizontalInset: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 8 : 0

    init() {
        super.init(frame: .zero)
        name.font = .preferredFont(forTextStyle: .headline)
        name.adjustsFontForContentSizeCategory = true
        name.lineBreakMode = .byTruncatingTail
        let row = UIStackView(arrangedSubviews: [avatar, name])
        row.spacing = 8; row.alignment = .center; row.isUserInteractionEnabled = false
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        name.widthAnchor.constraint(lessThanOrEqualToConstant: maximumNameWidth).isActive = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (header: MobileConversationHeaderView, _) in
            header.invalidateIntrinsicContentSize()
        }
    }
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        let labelSize = name.intrinsicContentSize
        return CGSize(width: horizontalInset * 2 + 28 + 8 + min(maximumNameWidth, max(0, labelSize.width)), height: max(28, labelSize.height))
    }

    func configure(_ chat: Chat) {
        if name.text != chat.displayTitle {
            name.text = chat.displayTitle
            invalidateIntrinsicContentSize()
        }
        avatar.configure(chat: chat)
    }
}
#endif
