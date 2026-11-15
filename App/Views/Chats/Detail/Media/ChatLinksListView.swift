import SwiftUI

/// Every link shared in a chat, newest first.
struct ChatLinksListView: View {
    let pager: ChatMessagePager
    /// Links found so far. Pages only add messages, so each is scanned once.
    @State private var links: [ChatSharedLink] = []
    @State private var scannedCount = 0

    var body: some View {
        List {
            ForEach(links) { link in
                ChatLinkRow(link: link)
                    .onAppear { loadMore(after: link) }
            }

            if pager.showsFooter {
                ChatMessagePagerFooter(pager: pager)
                    .listRowSeparator(.hidden)
            }
        }
        .contentMargins(.top, 10, for: .scrollContent)
        .onChange(of: pager.items.count, initial: true) { _, count in
            guard count > scannedCount else { return }
            links += ChatSharedLink.links(in: pager.items[scannedCount...])
            scannedCount = count
        }
        .overlay {
            if pager.hasLoaded, links.isEmpty, !pager.isLoading, !pager.isLoadingServerHistory {
                ContentUnavailableView(ChatMediaKind.links.emptyTitle, systemImage: ChatMediaKind.links.systemImage)
            }
        }
    }

    private func loadMore(after link: ChatSharedLink) {
        guard link.id == links.last?.id else { return }
        Task { await pager.loadNextPage() }
    }
}
