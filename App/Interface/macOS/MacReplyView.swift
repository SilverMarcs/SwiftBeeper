#if os(macOS)
import AppKit

@MainActor
final class MacReplyView: NSView {
    private let sender = NSTextField(labelWithString: "")
    private let quote = NSTextField(labelWithString: "")
    private let onOpen: () -> Void
    init(message: Message, onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
        let rule = NSView(); rule.wantsLayer = true; rule.layer?.backgroundColor = NSColor.controlAccentColor.cgColor; rule.layer?.cornerRadius = 1.5
        sender.stringValue = message.senderDisplayName; sender.font = .systemFont(ofSize: 11, weight: .bold); sender.textColor = .secondaryLabelColor
        quote.stringValue = message.displayText; quote.font = .systemFont(ofSize: 11); quote.textColor = .secondaryLabelColor; quote.lineBreakMode = .byTruncatingTail
        quote.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let labels = NSStackView(vertical: [sender, quote], spacing: 2)
        let row = NSStackView(views: [rule, labels]); row.spacing = 6
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), row.topAnchor.constraint(equalTo: topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), rule.widthAnchor.constraint(equalToConstant: 3), rule.heightAnchor.constraint(equalTo: labels.heightAnchor)])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(open)))
    }
    override var intrinsicContentSize: NSSize {
        NSSize(width: max(sender.intrinsicContentSize.width, min(360, quote.intrinsicContentSize.width)) + 25, height: sender.intrinsicContentSize.height + quote.intrinsicContentSize.height + 10)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func open() { onOpen() }
}
#endif
