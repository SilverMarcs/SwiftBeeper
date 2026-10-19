#if os(macOS)
import AppKit

@MainActor
final class MacMessageRowView: NSTableCellView {
    private var root: NSStackView?
    var onJump: ((String) -> Void)?
    var onProfile: ((ChatParticipant) -> Void)?
    var onPreview: ((Attachment) -> Void)?

    func configure(_ row: TimelineRow, chat: Chat, context: AppContext) {
        root?.removeFromSuperview()
        let outgoing = row.message?.isOutgoing(in: chat) ?? true
        let column = NSStackView(vertical: [], spacing: 4)
        column.alignment = outgoing ? .trailing : .leading
        let outer = NSStackView(vertical: [], spacing: 6)
        outer.alignment = .centerX
        if row.showsTimestamp {
            let date = label(TimelineDate.label(for: row.timestamp)); date.alignment = .center
            outer.addArrangedSubview(date)
        }
        if row.isUnreadBoundary {
            let unread = label("New Messages"); unread.font = .systemFont(ofSize: 10, weight: .bold)
            let rule = NSStackView(); rule.spacing = 8
            for child in [NSBox(), unread, NSBox()] { if let line = child as? NSBox { line.boxType = .separator }; rule.addArrangedSubview(child) }
            if let first = rule.arrangedSubviews.first, let last = rule.arrangedSubviews.last { first.widthAnchor.constraint(equalTo: last.widthAnchor).isActive = true }
            outer.addArrangedSubview(rule)
            rule.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        }
        if let message = row.message, row.showsSender && !outgoing && chat.isGroupChat {
            let sender = MacActionButton(message.senderDisplayName) { [weak self] in
                if let participant = chat.participant(with: message.senderID) { self?.onProfile?(participant) }
            }
            sender.isBordered = false; sender.font = .systemFont(ofSize: 12, weight: .bold)
            column.addArrangedSubview(sender)
        }
        if let linked = row.linkedMessage {
            let quote = MacReplyView(message: linked) { [weak self] in self?.onJump?(linked.id) }
            column.addArrangedSubview(quote)
        } else if row.message?.linkedMessageID?.isBlank == false || row.outgoing?.replyToMessageID?.isBlank == false {
            column.addArrangedSubview(label("Reply to an earlier message"))
        }
        if let message = row.message, message.isDeletedMessage {
            addText(message.displayText, message: message, chat: chat, outgoing: outgoing, to: column)
        } else {
            for attachment in row.message?.attachments ?? [] {
                let media = MacAttachmentView(attachment: attachment, context: context, title: chat.displayTitle, outgoing: outgoing)
                media.onPreview = { [weak self] in self?.onPreview?(attachment) }
                column.addArrangedSubview(media)
            }
            let text = row.text
            if !text.isEmpty { addText(text, message: row.message, chat: chat, outgoing: outgoing, to: column) }
        }
        if let pending = row.outgoing {
            for attachment in pending.attachments {
                column.addArrangedSubview(MacPendingAttachmentView(attachment))
                if let progress = pending.uploadProgressByAttachmentID[attachment.id] {
                    let indicator = NSProgressIndicator(); indicator.isIndeterminate = false; indicator.doubleValue = progress * 100
                    column.addArrangedSubview(indicator)
                }
            }
            switch pending.state {
            case .sending: break
            case .failed(let error):
                let retry = MacActionButton("Retry — " + error) { context.chats.retrySending(pending.id) }
                retry.contentTintColor = .systemRed; column.addArrangedSubview(retry)
            }
        }
        if let message = row.message, let groups = message.groupedReactions, !groups.isEmpty {
            let reactions = NSStackView(); reactions.spacing = 4
            for group in groups {
                let action = ConversationActions.reaction(group.reactionKey, message: message, chat: chat, store: context.chats)
                let button = MacActionButton(group.reactionKey + (group.count > 1 ? " \(group.count)" : ""), action: action.perform)
                button.isBordered = false; button.font = .systemFont(ofSize: 11)
                button.wantsLayer = true; button.layer?.cornerRadius = 9
                button.layer?.backgroundColor = (action.selected ? NSColor.controlAccentColor.withAlphaComponent(0.3) : .quaternaryLabelColor).cgColor
                button.layer?.borderColor = NSColor.controlAccentColor.cgColor; button.layer?.borderWidth = action.selected ? 1 : 0
                button.widthAnchor.constraint(equalToConstant: button.attributedTitle.size().width + 12).isActive = true
                button.heightAnchor.constraint(equalToConstant: 18).isActive = true
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
            let receipt = NSStackView(views: [read])
            receipt.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 3)
            column.addArrangedSubview(receipt)
        }

        let lane = NSStackView(); lane.spacing = 6; lane.alignment = .bottom
        let spacer = NSView(); spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if outgoing { lane.addArrangedSubview(spacer) }
        else if !chat.isSingleChat {
            let avatar = MacAvatarView(size: 28)
            avatar.configure(name: row.message?.senderDisplayName ?? chat.displayTitle, source: row.message.flatMap { chat.participant(with: $0.senderID)?.imgURL } ?? chat.imgURL)
            avatar.alphaValue = row.showsAvatar ? 1 : 0
            avatar.onOpen = { [weak self] in
                guard let message = row.message, let participant = chat.participant(with: message.senderID) else { return }
                self?.onProfile?(participant)
            }
            lane.addArrangedSubview(avatar)
        }
        lane.addArrangedSubview(column)
        if !outgoing { lane.addArrangedSubview(spacer) }
        outer.addArrangedSubview(lane)
        addSubview(outer); outer.translatesAutoresizingMaskIntoConstraints = false
        // Include the preceding row's 2pt bottom inset when balancing divider spacing.
        let topInset: CGFloat = row.showsTimestamp || row.isUnreadBoundary ? outer.spacing - 2 : 2
        NSLayoutConstraint.activate([outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18), outer.topAnchor.constraint(equalTo: topAnchor, constant: topInset), outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)])
        lane.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        column.widthAnchor.constraint(lessThanOrEqualTo: outer.widthAnchor, constant: outgoing || chat.isSingleChat ? -56 : -90).isActive = true
        root = outer
    }

    private func addText(_ value: String, message: Message?, chat: Chat, outgoing: Bool, to column: NSStackView) {
        let text = NSTextField(wrappingLabelWithString: "")
        text.attributedStringValue = MessageText.attributed(value, message: message, chat: chat, outgoing: outgoing)
        text.isSelectable = true
        text.allowsExpansionToolTips = false
        text.allowsEditingTextAttributes = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bubble = MacBubbleView(outgoing: outgoing)
        bubble.addSubview(text); text.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12), text.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12), text.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8), text.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8)])
        column.addArrangedSubview(bubble)
        bubble.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor).isActive = true
    }

    private func label(_ value: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.allowsExpansionToolTips = false
        label.font = .preferredFont(forTextStyle: .caption1); label.textColor = .secondaryLabelColor
        return label
    }
}
#endif
