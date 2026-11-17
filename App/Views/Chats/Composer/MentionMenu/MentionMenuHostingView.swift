#if os(macOS)
import SwiftUI

/// Takes the first click, so a member is picked without the panel having to
/// become key first.
final class MentionMenuHostingView: NSHostingView<MentionMenuView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
#endif
