#if os(macOS)
import AppKit

@MainActor
final class MacAvatarView: NSView {
    private let dimension: CGFloat
    private var parts: [AvatarPart] = []
    private var groupViews: [MacAvatarView] = []
    private let imageView = NSImageView()
    private let initials = NSTextField(labelWithString: "")
    private var imageTask: Task<Void, Never>?
    private var source: String?
    var onOpen: (() -> Void)?

    init(size: CGFloat) {
        dimension = size
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = size / 2
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        imageView.pinEdges(to: self)
        initials.font = .systemFont(ofSize: size * 0.38, weight: .medium)
        initials.alignment = .center
        initials.translatesAutoresizingMaskIntoConstraints = false
        addSubview(initials)
        NSLayoutConstraint.activate([initials.centerXAnchor.constraint(equalTo: centerXAnchor), initials.centerYAnchor.constraint(equalTo: centerYAnchor)])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(open)))
    }

    required init?(coder: NSCoder) { nil }

    func configure(chat: Chat) {
        if chat.imgURL?.isBlank != false && chat.isGroupChat {
            let next = AvatarPart.group(for: chat)
            imageTask?.cancel(); source = nil; imageView.image = nil; initials.isHidden = true
            guard parts != next else { return }
            groupViews.forEach { $0.removeFromSuperview() }; groupViews = []; parts = next
            for part in next {
                let child = MacAvatarView(size: dimension * part.size)
                child.configure(name: part.name, source: part.source)
                addSubview(child); groupViews.append(child)
                NSLayoutConstraint.activate([child.centerXAnchor.constraint(equalTo: centerXAnchor, constant: dimension * part.x), child.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -dimension * part.y)])
            }
        } else {
            configure(name: chat.otherParticipant?.displayName ?? chat.preview?.senderName ?? chat.displayTitle, source: chat.imgURL ?? chat.otherParticipant?.imgURL)
        }
    }

    func configure(name: String, source: String?) {
        groupViews.forEach { $0.removeFromSuperview() }; groupViews = []; parts = []
        initials.isHidden = imageView.image != nil
        initials.stringValue = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        guard self.source != source else { return }
        self.source = source
        imageTask?.cancel()
        imageView.image = nil
        initials.isHidden = false
        guard let source else { return }
        imageTask = Task { [weak self] in
            let image = await NativeImages.image(source, maximumSize: 200)
            guard !Task.isCancelled, let self else { return }
            imageView.image = image
            initials.isHidden = image != nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor }
    }

    @objc private func open() { onOpen?() }
}
#endif
