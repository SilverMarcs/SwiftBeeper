#if os(iOS)
import SwiftUI

/// Replaces the search icon, hides the clear button, and keeps body text.
/// UIKit refreshes the search field during toolbar and focus transitions, so
/// enforce its styling synchronously instead of waiting for a SwiftUI update.
final class ComposerSearchFieldStyle: UIView {
    private weak var textField: UISearchTextField?
    private var observations: [NSKeyValueObservation] = []
    private var isApplyingStyle = false

    init(textField: UISearchTextField) {
        self.textField = textField
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        textField.adjustsFontForContentSizeCategory = true
        let updateStyle: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.applyStyle()
            }
        }
        observations = [
            textField.observe(\.font) { _, _ in updateStyle() },
            textField.observe(\.defaultTextAttributes) { _, _ in updateStyle() },
            textField.observe(\.attributedText) { _, _ in updateStyle() },
            textField.observe(\.attributedPlaceholder) { _, _ in updateStyle() },
            textField.observe(\.clearButtonMode) { _, _ in updateStyle() }
        ]
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitLegibilityWeight.self]) {
            (view: ComposerSearchFieldStyle, _: UITraitCollection) in
            view.applyStyle()
        }
        applyStyle()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func applyStyle() {
        guard !isApplyingStyle, let textField else { return }
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: textField.traitCollection)
        isApplyingStyle = true
        defer { isApplyingStyle = false }
        if textField.clearButtonMode != .never {
            textField.clearButtonMode = .never
        }
        if textField.font != font {
            textField.font = font
        }
        // UIKit can replace the placeholder's attributes without changing `font`.
        if let placeholder = textField.attributedPlaceholder, placeholder.length > 0,
           placeholder.attribute(.font, at: 0, effectiveRange: nil) as? UIFont != font {
            let styledPlaceholder = NSMutableAttributedString(attributedString: placeholder)
            styledPlaceholder.addAttribute(.font, value: font, range: NSRange(location: 0, length: placeholder.length))
            textField.attributedPlaceholder = styledPlaceholder
        }
    }
}
#endif
