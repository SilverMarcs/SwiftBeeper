import SwiftUI

/// A chat as a selectable chat list row.
struct ChatListRow: View {
    let chat: Chat
    /// The logo badging the avatar; nil shows the plain avatar.
    let networkImageURL: String?
    /// Hides the bottom separator, so none runs along the edges of the
    /// iPad's selected row highlight.
    var hidesBottomSeparator = false

    var body: some View {
        ChatRowView(chat: chat, networkImageURL: networkImageURL)
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparator(hidesBottomSeparator ? .hidden : .visible, edges: .bottom)
            .if(isMacOrPad) {
                $0.listRowSeparatorTint(.primary.opacity(0.1), edges: .bottom)
            }
            .tag(chat.id)
    }
}
