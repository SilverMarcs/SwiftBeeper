#if os(iOS)
import UIKit

@MainActor
final class MobileMessageCell: UITableViewCell {
    private let horizontalInset: CGFloat = 15
    private var groupIncoming = false
    private var root: UIStackView?
    private var maximumTextWidth: CGFloat {
        max(40, contentView.bounds.width - horizontalInset * 2 - (groupIncoming ? 90 : 56))
    }
    var onJump: ((String) -> Void)?
    var onProfile: ((ChatParticipant) -> Void)?
    var onPreview: ((Attachment) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none; backgroundColor = .clear
    }
    required init?(coder: NSCoder) { nil }
    func configure(_ row: TimelineRow, chat: Chat, context: AppContext) {
        root?.removeFromSuperview()
        let outgoing = row.message?.isOutgoing(in: chat) ?? true
        groupIncoming = !outgoing && !chat.isSingleChat
        let column = UIStackView(vertical: [], spacing: 4); column.alignment = outgoing ? .trailing : .leading
        let outer = UIStackView(vertical: [], spacing: 8); outer.alignment = .center
        if row.showsTimestamp { outer.addArrangedSubview(label(TimelineDate.label(for: row.timestamp))) }
        if row.isUnreadBoundary { let unread = label("New Messages"); unread.font = .preferredFont(forTextStyle: .caption1).withTraits(.traitBold); outer.addArrangedSubview(unread) }
        if let message = row.message, row.showsSender && !outgoing && chat.isGroupChat {
            let sender = UIButton(type: .system); sender.setTitle(message.senderDisplayName, for: .normal); sender.titleLabel?.font = .preferredFont(forTextStyle: .subheadline).withTraits(.traitBold)
            sender.setTitleColor(.label, for: .normal)
            sender.addAction(UIAction { [weak self] _ in if let person = chat.participant(with: message.senderID) { self?.onProfile?(person) } }, for: .touchUpInside)
            column.addArrangedSubview(sender)
        }
        if let linked = row.linkedMessage {
            let quote = MobileReplyView(message: linked) { [weak self] in self?.onJump?(linked.id) }
            column.addArrangedSubview(quote)
        } else if row.message?.linkedMessageID?.isBlank == false || row.outgoing?.replyToMessageID?.isBlank == false { column.addArrangedSubview(label("Reply to an earlier message")) }
        if let message = row.message, message.isDeletedMessage {
            addText(message.displayText, message: message, chat: chat, outgoing: outgoing, to: column)
        } else {
            for attachment in row.message?.attachments ?? [] {
                let media = MobileAttachmentView(attachment: attachment, context: context, title: chat.displayTitle, outgoing: outgoing)
                media.onPreview = { [weak self] in self?.onPreview?(attachment) }; column.addArrangedSubview(media)
            }
            if !row.text.isEmpty { addText(row.text, message: row.message, chat: chat, outgoing: outgoing, to: column) }
        }
        if let pending = row.outgoing {
            for attachment in pending.attachments {
                column.addArrangedSubview(MobilePendingAttachmentView(attachment))
                if let value = pending.uploadProgressByAttachmentID[attachment.id] { let progress = UIProgressView(progressViewStyle: .default); progress.progress = Float(value); column.addArrangedSubview(progress) }
            }
            switch pending.state {
            case .sending: break
            case .failed(let error):
                let retry = UIButton(type: .system); retry.setTitle("Retry — " + error, for: .normal); retry.tintColor = .systemRed
                retry.addAction(UIAction { _ in context.chats.retrySending(pending.id) }, for: .touchUpInside); column.addArrangedSubview(retry)
            }
        }
        if let message = row.message, let groups = message.groupedReactions, !groups.isEmpty {
            let reactions = UIStackView(); reactions.spacing = 4
            for group in groups {
                let action = ConversationActions.reaction(group.reactionKey, message: message, chat: chat, store: context.chats)
                let button = UIButton(type: .system); var config = UIButton.Configuration.plain()
                config.title = group.reactionKey + (group.count > 1 ? " \(group.count)" : "")
                config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in var outgoing = incoming; outgoing.font = .preferredFont(forTextStyle: .caption1); return outgoing }
                config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
                config.cornerStyle = .capsule; config.baseForegroundColor = .label
                config.background.backgroundColor = action.selected ? UIColor.tintColor.withAlphaComponent(0.3) : .quaternarySystemFill
                config.background.strokeColor = action.selected ? .tintColor : .clear; config.background.strokeWidth = action.selected ? 1 : 0
                button.configuration = config
                button.addAction(UIAction { _ in action.perform() }, for: .touchUpInside)
                reactions.addArrangedSubview(button)
            }
            if let bubble = column.arrangedSubviews.last {
                column.addSubview(reactions); reactions.translatesAutoresizingMaskIntoConstraints = false
                reactions.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 1).isActive = true
                if outgoing { reactions.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -15).isActive = true }
                else { reactions.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: 15).isActive = true }
            }
        }

        if row.showsReadIndicator {
            let read = label("Read"); read.font = .preferredFont(forTextStyle: .caption2)
            let receipt = UIStackView(arrangedSubviews: [read])
            receipt.isLayoutMarginsRelativeArrangement = true
            receipt.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 3)
            column.addArrangedSubview(receipt)
        }

        let lane = UIStackView(); lane.spacing = 6; lane.alignment = .bottom
        let spacer = UIView(); spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        if outgoing { lane.addArrangedSubview(spacer) }
        else if !chat.isSingleChat {
            let avatar = MobileAvatarView(size: 28)
            avatar.configure(name: row.message?.senderDisplayName ?? chat.displayTitle, source: row.message.flatMap { chat.participant(with: $0.senderID)?.imgURL } ?? chat.imgURL)
            avatar.alpha = row.showsAvatar ? 1 : 0
            avatar.onOpen = { [weak self] in guard let id = row.message?.senderID, let person = chat.participant(with: id) else { return }; self?.onProfile?(person) }
            lane.addArrangedSubview(avatar)
        }
        lane.addArrangedSubview(column)
        if !outgoing { lane.addArrangedSubview(spacer) }
        outer.addArrangedSubview(lane); contentView.addSubview(outer); outer.translatesAutoresizingMaskIntoConstraints = false
        // Include the preceding cell's 2pt bottom inset when balancing divider spacing.
        let topInset: CGFloat = row.showsTimestamp || row.isUnreadBoundary ? outer.spacing - 2 : 2
        NSLayoutConstraint.activate([outer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset), outer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset), outer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: topInset), outer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2)])
        lane.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        column.widthAnchor.constraint(lessThanOrEqualTo: outer.widthAnchor, constant: groupIncoming ? -90 : -56).isActive = true
        root = outer
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        updateTextWidth(in: contentView)
    }
    private func updateTextWidth(in view: UIView) {
        if let text = view as? MobileMessageTextView { text.maximumWidth = maximumTextWidth }
        for child in view.subviews { updateTextWidth(in: child) }
    }
    private func addText(_ value: String, message: Message?, chat: Chat, outgoing: Bool, to column: UIStackView) {
        let text = MobileMessageTextView(); text.maximumWidth = maximumTextWidth; text.isEditable = false; text.isScrollEnabled = false
        text.isSelectable = true; text.adjustsFontForContentSizeCategory = true
        text.attributedText = MessageText.attributed(value, message: message, chat: chat, outgoing: outgoing)
        text.linkTextAttributes = [.foregroundColor: outgoing ? UIColor.white : UIColor.tintColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        text.textContainerInset = UIEdgeInsets(top: 10, left: 13, bottom: 10, right: 13)
        text.textContainer.lineFragmentPadding = 0
        text.outgoing = outgoing
        text.backgroundColor = outgoing ? .clear : UIColor { traits in traits.userInterfaceStyle == .dark ? .tertiarySystemBackground : .secondarySystemBackground }
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        column.addArrangedSubview(text)
        text.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor).isActive = true
    }
    private func label(_ value: String) -> UILabel {
        let label = UILabel(); label.text = value; label.font = .preferredFont(forTextStyle: .caption1); label.adjustsFontForContentSizeCategory = true; label.textColor = .secondaryLabel; label.numberOfLines = 0; return label
    }
}
#endif
