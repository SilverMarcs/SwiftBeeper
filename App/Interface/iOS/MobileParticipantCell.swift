#if os(iOS)
import UIKit

@MainActor
final class MobileParticipantCell: UITableViewCell {
    private let avatar = MobileAvatarView(size: 32)
    private let name = UILabel()
    private let you = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        name.font = .preferredFont(forTextStyle: .body); name.adjustsFontForContentSizeCategory = true
        you.font = .preferredFont(forTextStyle: .caption1); you.textColor = .secondaryLabel
        avatar.isUserInteractionEnabled = false
        let row = UIStackView(arrangedSubviews: [avatar, name, UIView(), you]); row.spacing = 10; row.alignment = .center
        contentView.addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor), row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor), row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6), row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)])
    }
    required init?(coder: NSCoder) { nil }
    func configure(_ participant: ChatParticipant) {
        avatar.configure(name: participant.displayName, source: participant.imgURL)
        name.text = participant.displayName; you.text = participant.isSelf == true ? "You" : nil
    }
}
#endif
