import SwiftUI

/// A chat as a selectable chat list row.
struct ChatListRow: View {
    let chat: Chat
    /// The logo badging the avatar; nil shows the plain avatar.
    let networkImageURL: String?

    var body: some View {
        ChatRowView(chat: chat, networkImageURL: networkImageURL)
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparator(.visible, edges: .bottom)
            .if(isMacOrPad) {
                $0.listRowSeparatorTint(.primary.opacity(0.1), edges: .bottom)
            }
            .tag(chat.id)
    }
}
