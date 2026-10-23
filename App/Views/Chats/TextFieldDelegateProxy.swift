#if os(iOS)
import UIKit

final class TextFieldDelegateProxy: NSObject, UITextFieldDelegate {
    weak var originalDelegate: UITextFieldDelegate?
    var shouldReturn: ((UITextField) -> Bool)?

    init(originalDelegate: UITextFieldDelegate?) {
        self.originalDelegate = originalDelegate
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(textFieldShouldReturn(_:)) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return originalDelegate
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let shouldReturn = shouldReturn {
            return shouldReturn(textField)
        }
        return originalDelegate?.textFieldShouldReturn?(textField) ?? true
    }
}
#endif
