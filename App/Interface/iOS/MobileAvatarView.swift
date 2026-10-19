#if os(iOS)
import UIKit

@MainActor
final class MobileAvatarView: UIControl {
    private let dimension: CGFloat
    private var parts: [AvatarPart] = []
    private var groupViews: [MobileAvatarView] = []
    private let image = UIImageView()
    private let initials = UILabel()
    private var source: String?
    private var task: Task<Void, Never>?
    var onOpen: (() -> Void)?

    init(size: CGFloat) {
        dimension = size
        super.init(frame: .zero)
        backgroundColor = .tertiarySystemFill; layer.cornerRadius = size / 2; clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
        image.contentMode = .scaleAspectFill; addSubview(image); image.pinEdges(to: self)
        initials.font = .systemFont(ofSize: size * 0.38, weight: .medium); initials.adjustsFontForContentSizeCategory = true; initials.textAlignment = .center
        addSubview(initials); initials.pinEdges(to: self)
        addAction(UIAction { [weak self] _ in self?.onOpen?() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { nil }
    func configure(chat: Chat) {
        if chat.imgURL?.isBlank != false && chat.isGroupChat {
            let next = AvatarPart.group(for: chat)
            task?.cancel(); source = nil; image.image = nil; initials.isHidden = true
            guard parts != next else { return }
            groupViews.forEach { $0.removeFromSuperview() }; groupViews = []; parts = next
            for part in next {
                let child = MobileAvatarView(size: dimension * part.size)
                child.configure(name: part.name, source: part.source); child.isUserInteractionEnabled = false
                addSubview(child); groupViews.append(child)
                NSLayoutConstraint.activate([child.centerXAnchor.constraint(equalTo: centerXAnchor, constant: dimension * part.x), child.centerYAnchor.constraint(equalTo: centerYAnchor, constant: dimension * part.y)])
            }
        } else {
            configure(name: chat.otherParticipant?.displayName ?? chat.preview?.senderName ?? chat.displayTitle, source: chat.imgURL ?? chat.otherParticipant?.imgURL)
        }
    }
    func configure(name: String, source: String?) {
        groupViews.forEach { $0.removeFromSuperview() }; groupViews = []; parts = []
        initials.isHidden = image.image != nil
        initials.text = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        guard self.source != source else { return }; self.source = source
        task?.cancel(); image.image = nil; initials.isHidden = false
        guard let source else { return }
        task = Task { [weak self] in
            let result = await NativeImages.image(source, maximumSize: 200)
            guard !Task.isCancelled, let self else { return }
            image.image = result; initials.isHidden = result != nil
        }
    }
    isolated deinit { task?.cancel() }
}
#endif
