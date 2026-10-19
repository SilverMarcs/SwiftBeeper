#if os(iOS)
import UIKit

@MainActor
final class MobileChatCell: UITableViewCell {
    private let avatar = MobileAvatarView(size: 42)
    private let titleLabel = UILabel()
    private let preview = UILabel()
    private let date = UILabel()
    private let badge = UILabel()
    private let badgeBackground = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        preview.textColor = .secondaryLabel; preview.numberOfLines = 1
        date.font = .preferredFont(forTextStyle: .subheadline); date.textColor = .secondaryLabel
        badge.font = .preferredFont(forTextStyle: .caption1).withTraits(.traitBold); badge.textAlignment = .center
        for label in [titleLabel, preview, date, badge] { label.adjustsFontForContentSizeCategory = true }
        badgeBackground.addSubview(badge); badge.translatesAutoresizingMaskIntoConstraints = false
        let badgeInsets = [badge.leadingAnchor.constraint(equalTo: badgeBackground.leadingAnchor, constant: 6), badge.trailingAnchor.constraint(equalTo: badgeBackground.trailingAnchor, constant: -6), badge.topAnchor.constraint(equalTo: badgeBackground.topAnchor, constant: 2), badge.bottomAnchor.constraint(equalTo: badgeBackground.bottomAnchor, constant: -2)]
        for constraint in badgeInsets { constraint.priority = .defaultHigh; constraint.isActive = true }
        badgeBackground.widthAnchor.constraint(greaterThanOrEqualTo: badgeBackground.heightAnchor).isActive = true
        let top = UIStackView(arrangedSubviews: [titleLabel, UIView(), date]); top.spacing = 8
        let bottom = UIStackView(arrangedSubviews: [preview, UIView(), badgeBackground]); bottom.spacing = 8
        // A hidden badge has zero width. Its roundness constraint must not
        // collapse the preview's height through the stack's fill alignment.
        bottom.alignment = .center
        let text = UIStackView(vertical: [top, bottom], spacing: 4)
        let row = UIStackView(arrangedSubviews: [avatar, text]); row.spacing = 8; row.alignment = .center
        contentView.addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 7), row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor, constant: -7), row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15), row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15)])
        for label in [titleLabel, preview] { label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeBackground.setContentCompressionResistancePriority(.required, for: .horizontal)
        avatar.isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        badgeBackground.layer.cornerRadius = badgeBackground.bounds.height / 2
    }
    func configure(_ chat: Chat) {
        titleLabel.text = chat.displayTitle
        titleLabel.font = chat.unreadCount > 0 ? .preferredFont(forTextStyle: .body).withTraits(.traitBold) : .preferredFont(forTextStyle: .body)
        preview.text = chat.previewText
        preview.font = .preferredFont(forTextStyle: .body)
        date.text = chat.lastActivityText
        badge.text = chat.unreadCount > 99 ? "99+" : chat.unreadCount.formatted()
        badge.textColor = chat.isMuted == true ? .secondaryLabel : .white
        badgeBackground.backgroundColor = chat.isMuted == true ? .secondaryLabel.withAlphaComponent(0.25) : .tintColor
        badgeBackground.isHidden = chat.unreadCount == 0
        avatar.configure(chat: chat)
    }
}
#endif
