#if os(iOS)
import UIKit

/// The UIKit fields behind a `.searchable` composer. UIKit shows clones of the
/// search field (such as the bottom-bar field), which don't follow changes to
/// the original, so each helper updates every field showing the composer.
/// Fields are told apart by their prompt, which no other search field shares.
@MainActor
enum ComposerSearchFields {
    /// `textField` and every clone of it UIKit shows.
    static func fields(matching textField: UISearchTextField, referenceView: UIView) -> [UISearchTextField] {
        guard let prompt = textField.placeholder, let window = referenceView.window else { return [] }
        return ([textField] + searchTextFields(in: window)).filter { $0.placeholder == prompt }
    }

    /// Uses regular body text and removes the magnifying glass, since the field
    /// composes messages. A zero-size leading view replaces the glyph so its
    /// slot takes no width; merely hiding the glyph keeps the slot.
    static func style(matching textField: UISearchTextField, referenceView: UIView) {
        for field in fields(matching: textField, referenceView: referenceView)
        where !(field.leftView is ComposerSearchFieldStyle) {
            field.leftView = ComposerSearchFieldStyle(textField: field)
        }
    }

    /// Shows the draft in fields UIKit emptied while closing. Fields being
    /// edited are left alone, as they already hold what was typed.
    static func restore(_ draft: String, matching textField: UISearchTextField, referenceView: UIView) {
        for field in fields(matching: textField, referenceView: referenceView)
        where !field.isFirstResponder && field.text != draft {
            field.text = draft
        }
    }

    private static func searchTextFields(in view: UIView) -> [UISearchTextField] {
        if let field = view as? UISearchTextField {
            return [field]
        }
        return view.subviews.flatMap(searchTextFields(in:))
    }
}
#endif
