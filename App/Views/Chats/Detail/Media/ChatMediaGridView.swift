import SwiftUI

/// Every photo and video in a chat, newest first.
struct ChatMediaGridView: View {
    let pager: ChatMessagePager

    var body: some View {
        ScrollView {
            ChatMediaGrid(
                messages: pager.items,
                columns: [GridItem(.adaptive(minimum: 96), spacing: ImageGalleryLayout.spacing)]
            ) {
                Task { await pager.loadNextPage() }
            }

            ChatMessagePagerFooter(pager: pager)
                .padding()
        }
        .overlay {
            if pager.isEmpty && !pager.isLoadingServerHistory {
                ContentUnavailableView(ChatMediaKind.media.emptyTitle, systemImage: ChatMediaKind.media.systemImage)
            }
        }
    }
}
