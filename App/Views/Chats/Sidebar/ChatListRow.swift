import SwiftUI

/// A chat as a selectable chat list row.
struct ChatListRow: View {
    let chat: Chat

    var body: some View {
        ChatRowView(chat: chat)
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparator(.visible, edges: .bottom)
            .if(isMacOrPad) {
                $0.listRowSeparatorTint(.primary.opacity(0.1), edges: .bottom)
            }
            .tag(chat.id)
    }
}
