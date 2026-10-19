#if os(macOS)
import AppKit

@MainActor
final class MacChatRowView: NSTableCellView {
    private let avatar = MacAvatarView(size: 42)
    private let title = NSTextField(labelWithString: "")
    private let preview = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let badgeBackground = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        textField = title
        title.lineBreakMode = .byTruncatingTail
        preview.lineBreakMode = .byTruncatingTail
        preview.textColor = .secondaryLabelColor
        date.font = .preferredFont(forTextStyle: .subheadline)
        date.textColor = .secondaryLabelColor
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.alignment = .center
        badgeBackground.wantsLayer = true
        badgeBackground.addSubview(badge)
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([badge.leadingAnchor.constraint(equalTo: badgeBackground.leadingAnchor, constant: 6), badge.trailingAnchor.constraint(equalTo: badgeBackground.trailingAnchor, constant: -6), badge.topAnchor.constraint(equalTo: badgeBackground.topAnchor, constant: 2), badge.bottomAnchor.constraint(equalTo: badgeBackground.bottomAnchor, constant: -2)])
        badgeBackground.widthAnchor.constraint(greaterThanOrEqualTo: badgeBackground.heightAnchor).isActive = true
        let top = NSStackView(views: [title, NSView(), date]); top.spacing = 8
        let bottom = NSStackView(views: [preview, NSView(), badgeBackground]); bottom.spacing = 8
        let text = NSStackView(vertical: [top, bottom], spacing: 4)
        let row = NSStackView(views: [avatar, text]); row.spacing = 8; row.alignment = .centerY
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for child in [date, badgeBackground] { child.setContentCompressionResistancePriority(.required, for: .horizontal) }
        for child in [top, bottom] { child.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        badgeBackground.layer?.cornerRadius = badgeBackground.bounds.height / 2
    }

    func configure(_ chat: Chat) {
        title.stringValue = chat.displayTitle
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: chat.unreadCount > 0 ? .bold : .regular)
        preview.stringValue = chat.previewText ?? ""
        preview.font = .systemFont(ofSize: NSFont.systemFontSize, weight: chat.unreadCount > 0 ? .medium : .regular)
        date.stringValue = chat.lastActivityText ?? ""
        badge.stringValue = chat.unreadCount > 99 ? "99+" : chat.unreadCount.formatted()
        badgeBackground.isHidden = chat.unreadCount == 0
        badge.textColor = chat.isMuted == true ? .secondaryLabelColor : .white
        badgeBackground.layer?.backgroundColor = (chat.isMuted == true ? NSColor.secondaryLabelColor.withAlphaComponent(0.25) : .controlAccentColor).cgColor
        avatar.configure(chat: chat)
    }
}
#endif
