#if os(iOS)
import SwiftUI

/// A full-size touch target without a separate background inside the glass bar.
struct ReactionAccessoryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
#endif
