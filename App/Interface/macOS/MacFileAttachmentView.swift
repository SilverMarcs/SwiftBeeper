#if os(macOS)
import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacFileAttachmentView: NSView {
    private let name = NSTextField(labelWithString: "")
    private let size = NSTextField(labelWithString: "")
    private let onOpen: () -> Void

    init(attachment: Attachment, outgoing: Bool, onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        super.init(frame: .zero)
        name.stringValue = attachment.fileName ?? "Attachment"; name.font = .preferredFont(forTextStyle: .callout); name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        size.stringValue = attachment.fileSize.map { Int64($0).formatted(.byteCount(style: .file)) } ?? ""
        size.font = .preferredFont(forTextStyle: .caption1); size.textColor = .secondaryLabelColor; size.isHidden = attachment.fileSize == nil
        let type = attachment.mimeType.flatMap { UTType(mimeType: $0) } ?? UTType(filenameExtension: URL(filePath: attachment.fileName ?? "").pathExtension) ?? .data
        let icon = NSImageView(image: NSWorkspace.shared.icon(for: type)); icon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 32), icon.heightAnchor.constraint(equalToConstant: 32)])
        let labels = NSStackView(vertical: [name, size], spacing: 2)
        let row = NSStackView(views: [icon, labels]); row.spacing = 8; row.alignment = .centerY
        let bubble = MacBubbleView(outgoing: outgoing, radius: 12); addSubview(bubble); bubble.pinEdges(to: self)
        bubble.addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12), row.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12), row.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8), row.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8)])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(open)))
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize {
        NSSize(width: 64 + max(name.intrinsicContentSize.width, size.intrinsicContentSize.width), height: max(32, name.intrinsicContentSize.height + (size.isHidden ? 0 : size.intrinsicContentSize.height + 2)) + 16)
    }
    @objc private func open() { onOpen() }
}
#endif
