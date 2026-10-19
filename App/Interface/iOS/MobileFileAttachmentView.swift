#if os(iOS)
import UIKit
import UniformTypeIdentifiers

@MainActor
final class MobileFileAttachmentView: UIControl {
    private let name = UILabel()
    private let size = UILabel()
    init(attachment: Attachment, outgoing: Bool, onOpen: @escaping () -> Void) {
        super.init(frame: .zero)
        name.text = attachment.fileName ?? "Attachment"; name.font = .preferredFont(forTextStyle: .callout); name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        size.text = attachment.fileSize.map { Int64($0).formatted(.byteCount(style: .file)) }
        size.font = .preferredFont(forTextStyle: .caption1); size.textColor = .secondaryLabel; size.isHidden = attachment.fileSize == nil
        let type = attachment.mimeType.flatMap { UTType(mimeType: $0) } ?? UTType(filenameExtension: URL(filePath: attachment.fileName ?? "").pathExtension) ?? .data
        let symbol: String
        if type.conforms(to: .image) { symbol = "photo" }
        else if type.conforms(to: .movie) || type.conforms(to: .video) { symbol = "film" }
        else if type.conforms(to: .audio) { symbol = "music.note" }
        else if type.conforms(to: .pdf) { symbol = "doc.richtext" }
        else if type.conforms(to: .archive) || type.conforms(to: .zip) { symbol = "doc.zipper" }
        else if type.conforms(to: .text) { symbol = "doc.text" }
        else { symbol = "doc" }
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .title1))); icon.tintColor = .secondaryLabel; icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 32), icon.heightAnchor.constraint(equalToConstant: 32)])
        let labels = UIStackView(vertical: [name, size], spacing: 2)
        let row = UIStackView(arrangedSubviews: [icon, labels]); row.spacing = 8; row.alignment = .center
        let bubble = MobileBubbleView(outgoing: outgoing); bubble.isUserInteractionEnabled = false
        addSubview(bubble); bubble.pinEdges(to: self)
        bubble.addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12), row.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12), row.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8), row.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8)])
        addAction(UIAction { _ in onOpen() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: CGSize {
        CGSize(width: 64 + max(name.intrinsicContentSize.width, size.intrinsicContentSize.width), height: max(32, name.intrinsicContentSize.height + (size.isHidden ? 0 : size.intrinsicContentSize.height + 2)) + 16)
    }
}
#endif
