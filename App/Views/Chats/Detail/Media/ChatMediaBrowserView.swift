import SwiftUI

/// A chat's photos and videos, files, or links, pushed from chat info.
struct ChatMediaBrowserView: View {
    let kind: ChatMediaKind
    @State private var pager: ChatMessagePager

    init(chatID: String, kind: ChatMediaKind) {
        self.kind = kind
        _pager = State(initialValue: ChatMessagePager(chatID: chatID) { cursor in
            try await APIClient.listChatMedia(chatID: chatID, kind: kind, cursor: cursor)
        })
    }

    var body: some View {
        Group {
            switch kind {
            case .media: ChatMediaGridView(pager: pager)
            case .files: ChatFilesListView(pager: pager)
            case .links: ChatLinksListView(pager: pager)
            }
        }
        .navigationTitle(Text(kind.title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ChatServerHistoryButton(pager: pager)
            }
        }
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .task {
            guard !pager.hasLoaded else { return }
            await pager.loadNextPage()
        }
    }
}
