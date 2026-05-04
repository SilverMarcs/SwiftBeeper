import SwiftUI

struct SessionRefreshGate<Content: View>: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch sessionStore.refreshState {
        case .idle:
            content()
        case .refreshing:
            loadingView("Refreshing session")
        case .failed:
            failedView
        }
    }

    private func loadingView(_ title: String) -> some View {
        ProgressView(title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(HiddenToolbarModifier())
    }

    private var failedView: some View {
        ContentUnavailableView {
            Label("Session Expired", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text("Couldn't reconnect to Beeper.")
        } actions: {
            Button("Reconnect") {
                Task {
                    guard (try? await sessionStore.refreshAccessToken()) != nil else { return }
                    await chatStore.loadChats()
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(HiddenToolbarModifier())
    }
}
