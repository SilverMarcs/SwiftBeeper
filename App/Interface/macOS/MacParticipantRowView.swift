#if os(macOS)
import AppKit

@MainActor
final class MacParticipantRowView: NSView {
    private let action: () -> Void
    init(_ participant: ChatParticipant, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        let avatar = MacAvatarView(size: 32); avatar.configure(name: participant.displayName, source: participant.imgURL)
        let name = NSTextField(labelWithString: participant.displayName); name.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let you = NSTextField(labelWithString: participant.isSelf == true ? "You" : ""); you.font = .preferredFont(forTextStyle: .caption1); you.textColor = .secondaryLabelColor
        let row = NSStackView(views: [avatar, name, NSView(), you]); row.spacing = 10
        addSubview(row); row.pinEdges(to: self)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(open)))
    }
    required init?(coder: NSCoder) { nil }
    @objc private func open() { action() }
}
#endif
