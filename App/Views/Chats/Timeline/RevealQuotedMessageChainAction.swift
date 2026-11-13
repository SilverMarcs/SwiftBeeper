import SwiftUI

/// Scrolls a reply down when the quoted messages above it reach past the top
/// of the timeline. The chain passes its top edge in the scroll view's space
/// and how many messages it holds, which grows as older quotes load.
struct RevealQuotedMessageChainAction {
    let action: (_ top: CGFloat, _ count: Int) -> Void

    func callAsFunction(top: CGFloat, count: Int) {
        action(top, count)
    }
}

extension EnvironmentValues {
    @Entry var revealQuotedMessageChain = RevealQuotedMessageChainAction { _, _ in }
}
