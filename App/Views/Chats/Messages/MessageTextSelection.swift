import SwiftUI

/// Whether message bubbles allow selecting part of their text. Selection
/// gives every bubble its own text view that lays the text out a second time
/// and takes part in cursor hit-testing, so turning it off makes long chats
/// scroll more smoothly.
enum MessageTextSelection {
    static let storageKey = "selectableMessageText"
}

extension EnvironmentValues {
    /// Set by the timeline from the user's setting.
    @Entry var selectsMessageText = true
}

extension View {
    /// Text selection for a message body, when the user's setting allows it.
    @ViewBuilder
    func messageTextSelection(_ isEnabled: Bool) -> some View {
        if isEnabled {
            textSelection(.enabled)
        } else {
            self
        }
    }
}
