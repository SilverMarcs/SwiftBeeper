#if os(iOS)
import UIKit

@MainActor
final class MobileComposerTextView: UITextView {
    var onImage: ((Data) -> Void)?
    var onFiles: (([URL]) -> Void)?
    var onSubmit: (() -> Void)?
    var onEditLast: (() -> Void)?
    var onCancel: (() -> Void)?
    var insertingNewline = false

    override func paste(_ sender: Any?) {
        if let urls = UIPasteboard.general.urls, urls.allSatisfy(\.isFileURL), !urls.isEmpty { onFiles?(urls); return }
        if let image = UIPasteboard.general.image, let data = image.pngData() { onImage?(data); return }
        super.paste(sender)
    }
    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        commands.append(UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(newline)))
        commands.append(UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(submit)))
        commands.append(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancel)))
        if text.isEmpty { commands.append(UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(editLast))) }
        return commands
    }
    @objc private func newline() { insertingNewline = true; insertText("\n"); insertingNewline = false }
    @objc private func submit() { onSubmit?() }
    @objc private func editLast() { onEditLast?() }
    @objc private func cancel() { onCancel?() }
}
#endif
