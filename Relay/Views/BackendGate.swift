import SwiftUI

struct BackendGate<Content: View>: View {
    let backend: EasyMatrixBackend
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch backend.state {
        case .idle, .starting, .stopping:
            // Only gate the very first startup. Later transitions through these
            // states (the foreground-recovery restart in `recoverIfNeeded()`,
            // shutdown on quit) keep the content up — a brief silent reconnect
            // instead of a full-screen "Quitting"/"Starting backend" takeover.
            if backend.hasEverBeenReady {
                content()
            } else {
                loadingView("Starting backend")
            }
        case .ready:
            content()
        case .crashed(let message):
            crashedView(message: message)
        }
    }

    private func loadingView(_ title: String) -> some View {
        ProgressView(title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(HiddenToolbarModifier())
    }

    private func crashedView(message: String) -> some View {
        ContentUnavailableView {
            Label("Backend failed to start", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await backend.start() }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(HiddenToolbarModifier())
    }
}
