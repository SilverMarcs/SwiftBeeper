#if os(iOS)
import UIKit

/// The text view behind `ComposerTextView`, with a placeholder, a single
/// truncated line at rest, and Return-to-send on hardware keyboards.
///
/// At rest it shows the draft's first line, centred in the field. While it
/// has focus it wraps the whole draft, growing a line at a time up to
/// `ComposerTextView.maximumLines` and scrolling beyond that.
final class ComposerEditor: UITextView {
    var onReturn: (() -> Void)?

    var placeholder = "" {
        didSet {
            guard placeholder != oldValue else { return }
            placeholderLabel.text = placeholder
            accessibilityLabel = placeholder
        }
    }

    /// Whether the editor wraps the whole draft, rather than its first line.
    var isGrowing = false {
        didSet {
            guard isGrowing != oldValue else { return }
            applyMode()
        }
    }

    /// The text's distance from the field's leading edge, as in the search
    /// field it replaced, and from the dictation or Send button after it.
    static let leadingInset: CGFloat = 20
    static let trailingInset: CGFloat = 8

    private let placeholderLabel = UILabel()

    init() {
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        font = .preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        textContainer.lineFragmentPadding = 0
        returnKeyType = .default
        autocapitalizationType = .sentences
        autocorrectionType = .yes
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = false
        // It sits on the bottom safe area's edge, which would otherwise inset
        // and shift its text.
        contentInsetAdjustmentBehavior = .never
        accessibilityIdentifier = "composer"

        placeholderLabel.font = font
        placeholderLabel.adjustsFontForContentSizeCategory = true
        // A search field's prompt color, which is dimmer than secondary
        // text in Dark Mode.
        placeholderLabel.textColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.38)
                : .secondaryLabel
        }
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (editor: ComposerEditor, _: UITraitCollection) in
            editor.setNeedsLayout()
            editor.invalidateIntrinsicContentSize()
        }
        applyMode()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Posted, with the editor, just before a change to the draft makes the
    /// composer grow or shrink, so the timeline can follow it.
    static let willResizeNotification = Notification.Name("ComposerEditor.willResize")

    /// The height the growing editor is growing or shrinking to.
    private var targetHeight: CGFloat = 0

    /// - Parameter announcesResize: Whether a change in height is announced
    ///   with `willResizeNotification`, for the timeline to follow.
    func textDidChange(announcesResize: Bool = true) {
        placeholderLabel.isHidden = !text.isEmpty
        if isGrowing, bounds.width > 0 {
            let height = Self.fittingHeight(of: text, width: bounds.width, maximumLines: ComposerTextView.maximumLines)
            if height != targetHeight {
                targetHeight = height
                if announcesResize {
                    NotificationCenter.default.post(name: Self.willResizeNotification, object: self)
                }
            }
        }
        updateScrolling()
    }

    /// At rest the editor shows the draft's first line, truncated. Growing,
    /// it wraps the whole draft.
    private func applyMode() {
        textContainer.maximumNumberOfLines = isGrowing ? 0 : 1
        textContainer.lineBreakMode = isGrowing ? .byWordWrapping : .byTruncatingTail
        // Growing, it always scrolls, so UIKit keeps the caret in view once
        // the draft outgrows it.
        isScrollEnabled = isGrowing
        contentOffset = .zero
        targetHeight = 0
        setNeedsLayout()
        if isGrowing {
            // Opening a long draft shows where the caret is, once laid out.
            Task { @MainActor [weak self] in
                guard let self, self.isGrowing else { return }
                self.layoutIfNeeded()
                self.scrollRangeToVisible(self.selectedRange)
            }
        }
    }

    /// The space above the first line and below the last: what centres a
    /// single line in the composer's row.
    private static func verticalInset(for font: UIFont) -> CGFloat {
        max((ComposerBarLayout.rowHeight - font.lineHeight) / 2, 0)
    }

    /// The editor's height at this width for `text`: its wrapped lines, from
    /// one up to `maximumLines`, measured as the editor lays them out. One
    /// line is exactly the composer's row.
    static func fittingHeight(of text: String, width: CGFloat, maximumLines: Int) -> CGFloat {
        let editor = measuringEditor
        let font = UIFont.preferredFont(forTextStyle: .body)
        let vertical = verticalInset(for: font)
        editor.font = font
        editor.textContainerInset = UIEdgeInsets(top: vertical, left: leadingInset, bottom: vertical, right: trailingInset)
        let fitting = CGSize(width: max(width, leadingInset + trailingInset + 1), height: .greatestFiniteMagnitude)
        editor.text = " "
        let oneLine = editor.sizeThatFits(fitting).height
        editor.text = text
        let height = text.isEmpty ? oneLine : editor.sizeThatFits(fitting).height
        let maximum = vertical * 2 + (oneLine - vertical * 2) * CGFloat(maximumLines)
        return ceil(max(min(max(height, oneLine), maximum), ComposerBarLayout.rowHeight))
    }

    private static let measuringEditor: ComposerEditor = {
        let editor = ComposerEditor()
        editor.isGrowing = true
        return editor
    }()

    private var lineHeight: CGFloat {
        (font ?? .preferredFont(forTextStyle: .body)).lineHeight
    }

    override func layoutSubviews() {
        let vertical: CGFloat
        if isGrowing {
            vertical = Self.verticalInset(for: font ?? .preferredFont(forTextStyle: .body))
        } else {
            vertical = max((bounds.height - lineHeight) / 2, 0)
        }
        let insets = UIEdgeInsets(top: vertical, left: Self.leadingInset, bottom: vertical, right: Self.trailingInset)
        if textContainerInset != insets {
            textContainerInset = insets
        }
        super.layoutSubviews()
        placeholderLabel.font = font
        placeholderLabel.frame = CGRect(
            x: insets.left, y: insets.top,
            width: max(bounds.width - insets.left - insets.right, 0), height: lineHeight
        )
        updateScrolling()
    }

    /// Scrolls only once the draft is taller than the editor can grow.
    /// A new line scrolls to the caret before the editor has grown to fit
    /// it; once the draft fits, its first line goes back to the top.
    ///
    /// While the editor grows to fit, it stays at the top rather than
    /// scrolling to the new line it hasn't grown to show yet.
    private func updateScrolling() {
        guard isGrowing, contentSize.height <= max(bounds.height, targetHeight) + 0.5, contentOffset.y != 0 else { return }
        contentOffset = .zero
    }

    // MARK: - Focus

    /// Until when the editor may take focus. UIKit hands focus back to the
    /// editor that last had it whenever its screen reappears, which would
    /// open the composer on returning to a chat; only a touch, VoiceOver or
    /// a request from the composer opens it.
    private var focusAllowedUntil: CFTimeInterval = 0

    func focus() {
        focusAllowedUntil = CACurrentMediaTime() + 1
        _ = becomeFirstResponder()
    }

    /// Leaving ends the window a touch opened.
    override func resignFirstResponder() -> Bool {
        focusAllowedUntil = 0
        return super.resignFirstResponder()
    }

    override func becomeFirstResponder() -> Bool {
        guard CACurrentMediaTime() < focusAllowedUntil else { return false }
        return super.becomeFirstResponder()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view != nil, event?.type == .touches {
            focusAllowedUntil = CACurrentMediaTime() + 2
        }
        return view
    }

    override func accessibilityActivate() -> Bool {
        focusAllowedUntil = CACurrentMediaTime() + 1
        return super.accessibilityActivate()
    }

    // MARK: - Hardware Return

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if sendsOnReturn(presses) {
            onReturn?()
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard !sendsOnReturn(presses) else { return }
        super.pressesEnded(presses, with: event)
    }

    /// Return on its own, outside a composition such as Japanese input.
    private func sendsOnReturn(_ presses: Set<UIPress>) -> Bool {
        guard markedTextRange == nil, presses.count == 1, let key = presses.first?.key,
              key.keyCode == .keyboardReturnOrEnter else { return false }
        return key.modifierFlags.isDisjoint(with: [.shift, .alternate, .command, .control])
    }
}
#endif
