import SwiftUI

/// Shows a quoted message, above the reply that quotes it, over the open
/// timeline. Reply previews run it when tapped.
struct ShowQuotedMessageAction {
    let action: (_ quoted: Message, _ reply: Message?) -> Void

    func callAsFunction(_ quoted: Message, reply: Message?) {
        action(quoted, reply)
    }
}

extension EnvironmentValues {
    @Entry var showQuotedMessage = ShowQuotedMessageAction { _, _ in }
}
