#if os(iOS)
import UIKit

/// A tap recognizer that recognizes alongside every other gesture and never
/// cancels or delays touches.
@MainActor
final class TimelineTapRecognizer: NSObject, UIGestureRecognizerDelegate {
    var onTap: (() -> Void)?
    private lazy var recognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(tapped))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        return recognizer
    }()

    func install(in scrollView: UIScrollView) {
        guard recognizer.view !== scrollView else { return }
        recognizer.view?.removeGestureRecognizer(recognizer)
        scrollView.addGestureRecognizer(recognizer)
    }

    func remove(from scrollView: UIScrollView) {
        guard recognizer.view === scrollView else { return }
        scrollView.removeGestureRecognizer(recognizer)
    }

    @objc private func tapped() {
        onTap?()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
