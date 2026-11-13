import SwiftUI

extension EnvironmentValues {
    /// True on a reply whose quoted messages are shown above it: its own
    /// quote recedes with the rest of the timeline, as the messages it
    /// stands for are already there.
    @Entry var recedesReplyPreview = false
}
