import SwiftUI

/// Every file shared in a chat, newest first.
struct ChatFilesListView: View {
    let pager: ChatMessagePager

    var body: some View {
        List {
            ForEach(pager.items) { message in
                if let attachment = message.attachments?.first {
                    ChatFileRow(message: message, attachment: attachment)
                        .onAppear { loadMore(after: message) }
                }
            }

            ChatMessagePagerFooter(pager: pager)
                .listRowSeparator(.hidden)
        }
        .contentMargins(.top, 10, for: .scrollContent)
        .overlay {
            if pager.isEmpty && !pager.isLoadingServerHistory {
                ContentUnavailableView(ChatMediaKind.files.emptyTitle, systemImage: ChatMediaKind.files.systemImage)
            }
        }
    }

    private func loadMore(after message: Message) {
        guard message.id == pager.items.last?.id else { return }
        Task { await pager.loadNextPage() }
    }
}
