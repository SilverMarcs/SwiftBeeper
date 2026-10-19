#if os(macOS)
import AppKit

@MainActor
final class MacPendingAttachmentView: NSView {
    private var task: Task<Void, Never>?

    init(_ attachment: PendingAttachment, onRemove: (() -> Void)? = nil) {
        super.init(frame: .zero)
        let image = NSImageView(); image.imageScaling = .scaleProportionallyUpOrDown
        image.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        let title = NSTextField(labelWithString: attachment.fileName); title.lineBreakMode = .byTruncatingMiddle
        let row = NSStackView(views: [image, title]); row.spacing = 8
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 38), image.heightAnchor.constraint(equalToConstant: 38)])
        if let onRemove { row.addArrangedSubview(MacActionButton("Remove \(attachment.fileName)", symbol: "xmark.circle", action: onRemove)) }
        addSubview(row); row.pinEdges(to: self)
        widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        if attachment.mimeType.hasPrefix("image/") {
            task = Task { [weak image] in
                let thumbnail = await NativeImages.thumbnail(attachment.fileData)
                guard !Task.isCancelled else { return }; image?.image = thumbnail
            }
        }
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { task?.cancel() }
}
#endif
