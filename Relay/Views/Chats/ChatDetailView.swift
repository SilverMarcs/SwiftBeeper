import SwiftUI

/// Platform dispatcher for the chat detail pane. The macOS and iOS
/// implementations live in `ChatDetailMac` / `ChatDetailiOS`; they're
/// identical for now but are kept separate so each can diverge as the
/// platforms' chat UIs grow apart.
struct ChatDetailView: View {
    var body: some View {
        #if os(macOS)
        ChatDetailMac()
        #else
        ChatDetailiOS()
        #endif
    }
}
