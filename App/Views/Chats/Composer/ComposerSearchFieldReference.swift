#if os(iOS)
import UIKit

/// The composer's search field and the introspector's coordinate reference,
/// as last found. Both stay owned by UIKit, and updating them doesn't
/// invalidate the SwiftUI view holding this.
@MainActor
final class ComposerSearchFieldReference {
    weak var textField: UISearchTextField?
    weak var referenceView: UIView?
}
#endif
