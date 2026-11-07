#if os(iOS)
import Observation
import UIKit

/// Whether the software keyboard is on screen, whichever field raised it.
/// Layout that makes room for the keyboard should follow this rather than
/// its own field's focus, since another field (such as the thread composer
/// beside the chat on iPad) can raise the keyboard just as well.
@MainActor
@Observable
final class KeyboardMonitor {
    static let shared = KeyboardMonitor()

    private(set) var isVisible = false

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isVisible = true }
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isVisible = false }
            },
        ]
    }
}
#endif
