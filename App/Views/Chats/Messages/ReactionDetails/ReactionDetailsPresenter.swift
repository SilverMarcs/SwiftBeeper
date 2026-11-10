import SwiftUI

/// Presents the reaction details sheet requested from a message's context menu.
struct ReactionDetailsPresenter: ViewModifier {
    @State private var details: ReactionDetails?

    func body(content: Content) -> some View {
        content
            .environment(\.showReactionDetails, ShowReactionDetailsAction { details = $0 })
            .sheet(item: $details) { details in
                ReactionDetailsSheet(details: details)
            }
    }
}
