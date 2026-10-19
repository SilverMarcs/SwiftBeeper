#if os(iOS)
import UIKit

@MainActor
final class MobilePendingAttachmentView: UIView {
    private var task: Task<Void, Never>?

    init(_ attachment: PendingAttachment, onRemove: (() -> Void)? = nil) {
        super.init(frame: .zero)
        let image = UIImageView(image: UIImage(systemName: "doc")); image.contentMode = .scaleAspectFit
        let title = UILabel(); title.text = attachment.fileName; title.font = .preferredFont(forTextStyle: .caption1); title.adjustsFontForContentSizeCategory = true; title.lineBreakMode = .byTruncatingMiddle
        let row = UIStackView(arrangedSubviews: [image, title]); row.spacing = 8; row.alignment = .center
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 38), image.heightAnchor.constraint(equalToConstant: 38)])
        if let onRemove {
            let remove = UIButton(type: .system); remove.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
            remove.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; remove.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            remove.addAction(UIAction { _ in onRemove() }, for: .touchUpInside); row.addArrangedSubview(remove)
        }
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
