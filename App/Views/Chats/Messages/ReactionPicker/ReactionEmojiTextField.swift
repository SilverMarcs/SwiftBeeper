#if os(iOS)
import UIKit

final class ReactionEmojiTextField: UITextField {
    var onSelection: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        textColor = .clear
        tintColor = .clear
        backgroundColor = .clear
        autocorrectionType = .no
        autocapitalizationType = .none
        returnKeyType = .done
        addTarget(self, action: #selector(textChanged), for: .editingChanged)
        // Tapping elsewhere or hiding the keyboard ends editing, and the pick.
        addTarget(self, action: #selector(cancel), for: [.editingDidEnd, .editingDidEndOnExit])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var textInputContextIdentifier: String? { "relay.reaction-emoji" }

    override var textInputMode: UITextInputMode? {
        // Prefer the enabled system emoji keyboard; do not construct private input modes.
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, window != nil, !isFirstResponder else { return }
            if !becomeFirstResponder() { onCancel?() }
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancel))]
    }

    @objc private func textChanged() {
        guard markedTextRange == nil else { return }
        let selection = text ?? ""
        text = ""
        onSelection?(selection)
    }

    @objc private func cancel() {
        onCancel?()
    }
}
#endif
