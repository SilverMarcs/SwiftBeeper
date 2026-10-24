import SwiftUI

/// Scrolls the open timeline to a loaded message. Reply previews use it to
/// jump to the message they quote.
struct ScrollToMessageAction {
    let action: (String) -> Void

    func callAsFunction(_ messageID: String) {
        action(messageID)
    }
}

extension EnvironmentValues {
    @Entry var scrollToMessage = ScrollToMessageAction { _ in }
}
