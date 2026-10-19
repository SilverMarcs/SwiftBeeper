#if os(macOS)
import AppKit

@MainActor
final class MacComposerView: NSView, NSTextViewDelegate {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private let text = MacComposerTextView()
    private let scroll = NSScrollView()
    private let textGlass = NSGlassEffectView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let attachments = NSStackView()
    private let attachmentScroll = NSScrollView()
    private var sendControl: NSView?
    private var cancelControl: NSView?
    private var normalLeading: NSLayoutConstraint?
    private var replyLeading: NSLayoutConstraint?
    private weak var attachmentButton: NSButton?
    private lazy var send = MacActionButton("Send", symbol: "arrow.up") { [weak self] in self?.submit() }
    private var attachmentIDs: [UUID] = []
    private var height: NSLayoutConstraint?
    var onChoosePhotos: (() -> Void)?
    var onSubmit: (() -> Void)?

    init(context: AppContext) {
        self.context = context
        super.init(frame: .zero)
        text.isRichText = false; text.font = .preferredFont(forTextStyle: .body)
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.delegate = self
        text.textContainerInset = NSSize(width: 7, height: 8)
        text.drawsBackground = false
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.registerForDraggedTypes([.fileURL])
        text.onSubmit = { [weak self] in self?.submit() }
        text.onEditLast = { [weak context] in context?.composer.editMostRecentOutgoingMessage() }
        text.onCancel = { [weak context] in context?.composer.cancelComposerAction() }
        text.onAttachments = { [weak self] urls in self?.importFiles(urls) }
        text.onImage = { [weak context] data, ext in
            guard let context, let chatID = context.chats.selectedChatID else { return }
            context.composer.addAttachment(data: data, fileName: "Pasted Image.\(ext)", mimeType: "image/\(ext)", to: chatID)
        }
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder; scroll.drawsBackground = false
        textGlass.contentView = scroll; scroll.pinEdges(to: textGlass); textGlass.cornerRadius = 20
        textGlass.translatesAutoresizingMaskIntoConstraints = false
        height = textGlass.heightAnchor.constraint(equalToConstant: 32); height?.isActive = true
        let attach = MacActionButton("Add", symbol: "plus") { [weak self] in self?.showAttachmentMenu() }
        attachmentButton = attach
        let attachGlass = circularControl(attach, tinted: false, diameter: 30)
        let sendGlass = circularControl(send, tinted: true, diameter: 28)
        sendControl = sendGlass
        let cancel = MacActionButton("Cancel Reply or Edit", symbol: "xmark") { [weak context] in context?.composer.cancelComposerAction() }
        let cancelGlass = circularControl(cancel, tinted: false, diameter: 28); cancelGlass.tintColor = .systemRed.withAlphaComponent(0.6); cancel.contentTintColor = .white
        cancelControl = cancelGlass
        let row = NSView()
        for control in [attachGlass, cancelGlass, textGlass, sendGlass] { row.addSubview(control) }
        NSLayoutConstraint.activate([
            attachGlass.leadingAnchor.constraint(equalTo: row.leadingAnchor), attachGlass.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -1),
            cancelGlass.leadingAnchor.constraint(equalTo: attachGlass.trailingAnchor, constant: 8), cancelGlass.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -1),
            textGlass.trailingAnchor.constraint(equalTo: sendGlass.leadingAnchor, constant: -8), textGlass.topAnchor.constraint(equalTo: row.topAnchor), textGlass.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            sendGlass.trailingAnchor.constraint(equalTo: row.trailingAnchor), sendGlass.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -2)
        ])
        normalLeading = textGlass.leadingAnchor.constraint(equalTo: attachGlass.trailingAnchor, constant: 8)
        replyLeading = textGlass.leadingAnchor.constraint(equalTo: cancelGlass.trailingAnchor, constant: 8)
        normalLeading?.isActive = true
        errorLabel.textColor = .systemRed
        attachments.orientation = .horizontal; attachments.alignment = .centerY; attachments.spacing = 8
        attachmentScroll.documentView = attachments; attachmentScroll.hasHorizontalScroller = true
        attachmentScroll.autohidesScrollers = true; attachmentScroll.drawsBackground = false
        attachmentScroll.translatesAutoresizingMaskIntoConstraints = false; attachments.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([attachmentScroll.heightAnchor.constraint(equalToConstant: 56), attachments.heightAnchor.constraint(equalTo: attachmentScroll.contentView.heightAnchor), attachments.topAnchor.constraint(equalTo: attachmentScroll.contentView.topAnchor), attachments.leadingAnchor.constraint(equalTo: attachmentScroll.contentView.leadingAnchor)])
        let root = NSStackView(vertical: [errorLabel, attachmentScroll, row], spacing: 8)
        let glassContainer = NSGlassEffectContainerView(); glassContainer.contentView = root
        addSubview(glassContainer); root.pinEdges(to: glassContainer); glassContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([glassContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), glassContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), glassContainer.topAnchor.constraint(equalTo: topAnchor, constant: 8), glassContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)])
        for child in [errorLabel, attachmentScroll, row] { child.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        textGlass.setContentHuggingPriority(.defaultLow, for: .horizontal)
        observation.track { [weak self] in self?.render() }
    }
    required init?(coder: NSCoder) { nil }

    private func circularControl(_ button: MacActionButton, tinted: Bool, diameter: CGFloat) -> NSGlassEffectView {
        button.isBordered = false
        button.contentTintColor = tinted ? .white : .secondaryLabelColor
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: tinted ? 15 : 17, weight: tinted ? .semibold : .bold))
        let glass = NSGlassEffectView(); glass.cornerRadius = diameter / 2
        glass.tintColor = tinted ? .controlAccentColor : nil
        glass.contentView = button; button.pinEdges(to: glass)
        glass.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([glass.widthAnchor.constraint(equalToConstant: diameter), glass.heightAnchor.constraint(equalToConstant: diameter)])
        return glass
    }

    private func render() {
        let input = context.composer
        let store = context.chats
        let draft = input.draft
        if text.string != draft { text.string = draft; resize() }
        text.isEditable = !input.cannotMessage && !input.isSavingEdit && store.selectedChatID != nil
        text.placeholder = input.messageFieldPrompt
        send.isEnabled = !input.sendButtonDisabled && !input.cannotMessage
        sendControl?.alphaValue = input.sendButtonDisabled ? 0.35 : 0.85
        send.image = NSImage(systemSymbolName: input.isEditing ? "checkmark" : "arrow.up", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        let active = input.hasActiveComposerAction
        cancelControl?.isHidden = !active
        normalLeading?.isActive = false; replyLeading?.isActive = false
        normalLeading?.isActive = !active; replyLeading?.isActive = active
        errorLabel.stringValue = store.messagesError ?? (input.cannotMessage ? "You can’t send messages to this participant." : "")
        errorLabel.isHidden = errorLabel.stringValue.isEmpty
        let pending = input.pendingAttachments
        if pending.map(\.id) != attachmentIDs {
            attachmentIDs = pending.map(\.id)
            attachments.arrangedSubviews.forEach { attachments.removeArrangedSubview($0); $0.removeFromSuperview() }
            for attachment in input.pendingAttachments {
                attachments.addArrangedSubview(MacPendingAttachmentView(attachment) { [weak input] in input?.removePendingAttachment(id: attachment.id) })
            }
        }
        attachmentScroll.isHidden = input.pendingAttachments.isEmpty
        if input.pendingFocus {
            Task { [weak self] in
                guard let self else { return }
                context.composer.pendingFocus = false
                window?.makeFirstResponder(text)
            }
        }
    }
    func textDidChange(_ notification: Notification) { text.needsDisplay = true; context.composer.draft = text.string; resize() }
    private func resize() {
        text.layoutManager?.ensureLayout(for: text.textContainer ?? NSTextContainer())
        let measured = text.textContainer.flatMap { text.layoutManager?.usedRect(for: $0).height } ?? 24
        height?.constant = min(128, max(32, measured + 16))
    }
    private func submit() {
        guard !context.composer.sendButtonDisabled, !context.composer.cannotMessage else { return }
        context.composer.handleSubmit(); onSubmit?()
    }
    private func showAttachmentMenu() {
        guard let button = attachmentButton else { return }
        let menu = NSMenu()
        menu.addItem(MacActionMenuItem(RelayAction(title: "Photos Library", symbol: "photo.on.rectangle.angled") { [weak self] in self?.onChoosePhotos?() }))
        menu.addItem(MacActionMenuItem(RelayAction(title: "Attach Files", symbol: "paperclip") { [weak self] in self?.chooseFiles() }))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }
    private func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }; self?.importFiles(panel.urls)
        }
    }
    private func importFiles(_ urls: [URL]) {
        guard let chatID = context.chats.selectedChatID else { return }
        for url in urls { context.composer.handleFileImport(.success(url), for: chatID) }
    }
}
#endif
