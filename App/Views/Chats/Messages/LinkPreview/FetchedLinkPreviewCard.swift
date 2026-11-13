import SwiftUI

/// The homeserver's preview card for a link, or nothing until it loads or
/// when the page has none.
struct FetchedLinkPreviewCard: View {
    let url: String
    let isOutgoing: Bool
    @State private var preview: MessageLinkPreview?

    /// Delay before fetching, so rows flicking past in a fast scroll don't.
    private static let fetchDelay: Duration = .milliseconds(300)

    init(url: String, isOutgoing: Bool) {
        self.url = url
        self.isOutgoing = isOutgoing
        // Lazy stacks recreate a row's state each time it scrolls back into
        // view; a cached preview shows in its first frame, without growing.
        _preview = State(initialValue: LinkPreviewLoader.shared.cachedPreview(for: url))
    }

    var body: some View {
        // A stable container, so the task isn't restarted when the card
        // replaces the empty placeholder.
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: 0, height: 0)
            if let preview, preview.url == url {
                MessageLinkPreviewCard(preview: preview, isOutgoing: isOutgoing)
            }
        }
        .task(id: url) {
            let loader = LinkPreviewLoader.shared
            if loader.isSettled(url) {
                preview = loader.cachedPreview(for: url)
                return
            }
            try? await Task.sleep(for: Self.fetchDelay)
            guard !Task.isCancelled else { return }
            let loaded = await loader.preview(for: url)
            guard !Task.isCancelled else { return }
            preview = loaded
        }
    }
}
