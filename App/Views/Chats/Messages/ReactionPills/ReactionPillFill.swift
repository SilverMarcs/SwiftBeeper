import SwiftUI

/// The accent color behind the user's own reactions, and otherwise the
/// incoming bubble's fill.
struct ReactionPillFill: View {
    let isOwn: Bool

    var body: some View {
        if isOwn {
            Color.accentColor
        } else {
            Color.clear.subtleBackground()
        }
    }
}
