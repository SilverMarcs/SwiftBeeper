import SwiftUI

struct BackendGate<Content: View>: View {
    let backend: EasyMatrixBackend
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch backend.state {
        case .idle, .starting:
            loadingView("Starting backend")
        case .stopping:
            loadingView("Quitting")
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
