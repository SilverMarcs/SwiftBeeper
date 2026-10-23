import SwiftUI

struct AppStartupView: View {
    @Environment(SessionStore.self) private var sessionStore
    @State private var ready = false
    @State private var errorMessage: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if ready {
                RootView()
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t open messages", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { attempt += 1 }
                }
            } else {
                ProgressView("Opening your messages…")
            }
        }
        .task(id: attempt) {
            do {
                errorMessage = nil
                try await MatrixRuntime.shared.start()
                let state = try await APIClient.manageState()
                sessionStore.isSignedIn = state.clientState?.isLoggedIn == true && state.clientState?.isVerified == true
                ready = true
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
