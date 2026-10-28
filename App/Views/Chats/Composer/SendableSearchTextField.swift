#if os(iOS)
import UIKit

/// Stands in for the composer's search field class so the keyboard's Send key
/// stays lit when only attachments are pending.
///
/// UIKit greys the Return key while `hasText` is false. Reporting text while
/// attachments are pending keeps it enabled however often the field's own
/// traits or text change. The field's class is swapped in place, so this adds
/// no stored properties.
final class SendableSearchTextField: UISearchTextField {
    /// Whether the composer has attachments to send. One composer is on screen.
    static var hasPendingAttachments = false

    override var hasText: Bool {
        super.hasText || Self.hasPendingAttachments
    }

    static func install(on field: UISearchTextField) {
        guard !(field is SendableSearchTextField) else { return }
        object_setClass(field, SendableSearchTextField.self)
    }
}
#endif
