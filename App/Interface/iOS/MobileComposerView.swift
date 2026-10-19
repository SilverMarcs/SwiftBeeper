#if os(iOS)
import UIKit

@MainActor
final class MobileComposerView: UIView, UITextViewDelegate, UIDropInteractionDelegate {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private let text = MobileComposerTextView()
    private let textGlass = UIVisualEffectView(effect: UIGlassEffect())
    private let placeholder = UILabel()
    private let attachments = UIStackView()
    private let attachmentScroll = UIScrollView()
    private let cancel = UIButton(type: .system)
    private let error = UILabel()
    private let send = UIButton(type: .system)
    private let attach = UIButton(type: .system)
    private var attachmentIDs: [UUID] = []
    private var height: NSLayoutConstraint?
    private var bottomPadding: NSLayoutConstraint?
    private var placeholderTop: NSLayoutConstraint?
    var onSubmit: (() -> Void)?
    var onChooseFiles: (() -> Void)?
    var onChoosePhotos: (() -> Void)?
    var onRequestFocus: (() -> Void)?
    var onFocus: (() -> Void)?

    init(context: AppContext) {
        self.context = context
        super.init(frame: .zero)
        backgroundColor = .clear
        text.font = .preferredFont(forTextStyle: .body); text.adjustsFontForContentSizeCategory = true
        text.delegate = self; text.returnKeyType = .send; text.enablesReturnKeyAutomatically = true
        text.backgroundColor = .clear
        textGlass.layer.cornerRadius = 20; textGlass.clipsToBounds = true
        textGlass.contentView.addSubview(text); text.pinEdges(to: textGlass.contentView)
        text.textContainerInset = UIEdgeInsets(top: 9, left: 8, bottom: 9, right: 8)
        text.isScrollEnabled = false
        placeholder.font = .preferredFont(forTextStyle: .body); placeholder.textColor = .placeholderText
        placeholder.isUserInteractionEnabled = false
        text.addSubview(placeholder); placeholder.translatesAutoresizingMaskIntoConstraints = false
        let placeholderTop = placeholder.topAnchor.constraint(equalTo: text.topAnchor, constant: 9)
        self.placeholderTop = placeholderTop
        NSLayoutConstraint.activate([placeholder.leadingAnchor.constraint(equalTo: text.leadingAnchor, constant: text.textContainerInset.left + text.textContainer.lineFragmentPadding), placeholderTop])
        var sendConfiguration = UIButton.Configuration.prominentGlass(); sendConfiguration.image = UIImage(systemName: "arrow.up"); sendConfiguration.cornerStyle = .capsule
        sendConfiguration.preferredSymbolConfigurationForImage = .init(pointSize: 16, weight: .semibold)
        send.configuration = sendConfiguration
        send.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        var attachConfiguration = UIButton.Configuration.glass(); attachConfiguration.image = UIImage(systemName: "plus"); attachConfiguration.cornerStyle = .capsule
        attach.configuration = attachConfiguration
        attach.menu = UIMenu(children: [UIAction(title: "Photos Library", image: UIImage(systemName: "photo.on.rectangle.angled")) { [weak self] _ in self?.onChoosePhotos?() }, UIAction(title: "Attach Files", image: UIImage(systemName: "paperclip")) { [weak self] _ in self?.onChooseFiles?() }]); attach.showsMenuAsPrimaryAction = true
        var cancelConfiguration = UIButton.Configuration.glass(); cancelConfiguration.image = UIImage(systemName: "xmark"); cancelConfiguration.cornerStyle = .capsule; cancelConfiguration.baseBackgroundColor = .systemRed
        cancel.configuration = cancelConfiguration
        cancel.addAction(UIAction { [weak context] _ in context?.composer.cancelComposerAction() }, for: .touchUpInside)
        error.font = .preferredFont(forTextStyle: .caption1); error.textColor = .systemRed; error.numberOfLines = 0
        attachments.axis = .horizontal; attachments.spacing = 8
        attachmentScroll.addSubview(attachments); attachments.translatesAutoresizingMaskIntoConstraints = false
        attachmentScroll.translatesAutoresizingMaskIntoConstraints = false
        let attachmentHeight = attachmentScroll.heightAnchor.constraint(equalToConstant: 52); attachmentHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([attachmentHeight, attachments.leadingAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.leadingAnchor), attachments.trailingAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.trailingAnchor), attachments.topAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.topAnchor), attachments.bottomAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.bottomAnchor), attachments.heightAnchor.constraint(equalTo: attachmentScroll.frameLayoutGuide.heightAnchor)])
        let row = UIStackView(arrangedSubviews: [attach, cancel, textGlass, send]); row.alignment = .bottom; row.spacing = 8
        let stack = UIStackView(vertical: [error, attachmentScroll, row], spacing: 8)
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        row.isHidden = isPhone
        addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        let bottomPadding = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: isPhone ? 0 : -2)
        self.bottomPadding = bottomPadding
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), stack.topAnchor.constraint(equalTo: topAnchor, constant: isPhone ? 0 : 8), bottomPadding])
        text.translatesAutoresizingMaskIntoConstraints = false
        height = textGlass.heightAnchor.constraint(equalToConstant: 44); height?.priority = .defaultHigh; height?.isActive = true
        // Keep the controls compact so the text field receives the row's width.
        textGlass.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for button in [attach, send, cancel] {
            for constraint in [button.widthAnchor.constraint(equalToConstant: 44), button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)] { constraint.priority = .defaultHigh; constraint.isActive = true }
        }
        text.onSubmit = { [weak self] in self?.submit() }
        text.onCancel = { [weak context] in context?.composer.cancelComposerAction() }
        text.onEditLast = { [weak context] in context?.composer.editMostRecentOutgoingMessage() }
        text.onImage = { [weak context] data in
            guard let context, let chatID = context.chats.selectedChatID else { return }
            context.composer.addAttachment(data: data, fileName: "Pasted Image.png", mimeType: "image/png", to: chatID)
        }
        text.onFiles = { [weak context] urls in
            guard let context, let chatID = context.chats.selectedChatID else { return }
            for url in urls { context.composer.handleFileImport(.success(url), for: chatID) }
        }
        addInteraction(UIDropInteraction(delegate: self))
        observation.track { [weak self] in self?.render() }
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() { super.layoutSubviews(); resize() }
    private func render() {
        let input = context.composer; let store = context.chats
        if text.text != input.draft { text.text = input.draft; resize() }
        text.isEditable = !input.cannotMessage && !input.isSavingEdit && store.selectedChatID != nil
        placeholder.text = input.messageFieldPrompt; placeholder.isHidden = !input.draft.isEmpty
        send.isEnabled = !input.sendButtonDisabled && !input.cannotMessage
        cancel.isHidden = !input.hasActiveComposerAction
        send.configuration?.image = UIImage(systemName: input.isEditing ? "checkmark" : "arrow.up")
        error.text = store.messagesError ?? (input.cannotMessage ? "You can’t send messages to this participant." : nil); error.isHidden = error.text == nil
        let pending = input.pendingAttachments
        if pending.map(\.id) != attachmentIDs {
            attachmentIDs = pending.map(\.id)
            attachments.arrangedSubviews.forEach { attachments.removeArrangedSubview($0); $0.removeFromSuperview() }
            for attachment in input.pendingAttachments {
                attachments.addArrangedSubview(MobilePendingAttachmentView(attachment) { [weak input] in input?.removePendingAttachment(id: attachment.id) })
            }
        }
        attachmentScroll.isHidden = input.pendingAttachments.isEmpty
        isHidden = store.selectedChatID == nil || (UIDevice.current.userInterfaceIdiom == .phone && error.isHidden && attachmentScroll.isHidden)
        if input.pendingFocus {
            Task { [weak self] in guard let self, context.composer.pendingFocus else { return }; context.composer.pendingFocus = false; if UIDevice.current.userInterfaceIdiom == .phone { onRequestFocus?() } else { text.becomeFirstResponder() } }
        }
    }
    private func resize() {
        let font = text.font ?? .preferredFont(forTextStyle: .body)
        // Balance the first line within the field's minimum height. Sharing this
        // inset with the placeholder keeps the hint, caret, and text aligned.
        let verticalInset = max(9, (44 - font.lineHeight) / 2)
        let insets = UIEdgeInsets(top: verticalInset, left: 8, bottom: verticalInset, right: 8)
        if text.textContainerInset != insets { text.textContainerInset = insets }
        if placeholder.font != font { placeholder.font = font }
        placeholderTop?.constant = verticalInset
        guard text.bounds.width > 0 else { return }
        let measured = text.sizeThatFits(CGSize(width: text.bounds.width, height: .greatestFiniteMagnitude)).height
        let value = min(160, max(44, measured))
        if height?.constant != value { height?.constant = value }
        text.isScrollEnabled = measured > 160
    }
    func textViewDidChange(_ textView: UITextView) { context.composer.draft = textView.text; placeholder.isHidden = !textView.text.isEmpty; resize() }
    func textViewDidBeginEditing(_ textView: UITextView) { updateBottomPadding(); onFocus?() }
    func textViewDidEndEditing(_ textView: UITextView) { updateBottomPadding() }
    private func updateBottomPadding() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        bottomPadding?.constant = text.isFirstResponder ? -8 : -2
    }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText value: String) -> Bool {
        if value == "\n" && !text.insertingNewline { submit(); return false }; return true
    }
    private func submit() { guard !context.composer.sendButtonDisabled, !context.composer.cannotMessage else { return }; context.composer.handleSubmit(); onSubmit?() }
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool { session.hasItemsConforming(toTypeIdentifiers: ["public.item"]) }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal { UIDropProposal(operation: .copy) }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) { _ = context.composer.handleDrop(session.items.map(\.itemProvider)) }
}
#endif
