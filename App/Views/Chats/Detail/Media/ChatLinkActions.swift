import SwiftUI

/// Copy and Share for a shared link's context menu.
struct ChatLinkActions: View {
    let url: URL

    var body: some View {
        Button("Copy Link", systemImage: "doc.on.doc") {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            #else
            UIPasteboard.general.url = url
            #endif
        }

        ShareLink(item: url)
    }
}
