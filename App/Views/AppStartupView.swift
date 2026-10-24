import SwiftUI

/// Starts the Matrix core and reads the sign-in state before showing `RootView`.
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
                sessionStore.isSignedIn = state.isLoggedIn && state.isVerified
                ready = true
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
