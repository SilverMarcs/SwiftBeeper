import SwiftUI

/// Recent chats, or search results while searching, with the selection marked.
/// Selecting a chat shows the composer below.
struct ShareChatList: View {
    let model: ShareModel

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView("Can’t Share", systemImage: "exclamationmark.bubble", description: Text(message))
            case .ready:
                List(model.visibleChats) { chat in
                    Button {
                        model.select(chat)
                    } label: {
                        ShareChatRow(model: model, chat: chat, isSelected: model.selectedChat == chat)
                    }
                    .buttonStyle(.plain)
                }
                #if os(iOS)
                .contentMargins(.top, 10, for: .scrollContent)
                #endif
                .overlay {
                    if model.searchResults?.isEmpty == true {
                        ContentUnavailableView.search(text: model.query)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.selectedChat != nil {
                ShareComposer(model: model)
            }
        }
    }
}
