import SwiftUI

extension EnvironmentValues {
    /// Fill for the user's own bubbles; the timeline sets it from the chat's network.
    @Entry var outgoingBubbleColor: Color = .accentColor
}
