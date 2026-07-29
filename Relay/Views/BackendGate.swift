import SwiftUI

struct BackendGate<Content: View>: View {
    let serverConnection: ServerConnection
    @ViewBuilder var content: () -> Content

    var body: some View {
        // `hasEverBeenReady` only ever flips false→true once, so once the
        // backend has come up we keep `content()` in a single, stable
        // structural slot for the rest of the session. Previously `content()`
        // was returned from two different `switch` arms (`.ready` and the
        // `.starting`/`.stopping` recovery branch); SwiftUI treats each arm of
        // a `switch` as a distinct identity, so the foreground-restart churn
        // (.ready → .stopping → .starting → .ready in `recoverIfNeeded()`)
        // moved content across `_ConditionalContent` slots and tore down /
        // rebuilt the whole ContentView tree twice. That reset every `@State`
        // underneath it — dismissing open sheets and flashing every avatar back
        // through its loading placeholder. Gating on the monotonic flag pins
        // content to one slot, and the crash UI overlays it instead of
        // replacing it so a crash+retry also preserves state.
        if serverConnection.hasEverBeenReady {
            content()
                .overlay {
                    if let message = serverConnection.failureMessage {
                        crashedView(message: message)
                            .background(.background)
                    }
                }
        } else {
            if let message = serverConnection.failureMessage {
                crashedView(message: message)
            } else {
                loadingView("Starting backend")
            }
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
                Task { await serverConnection.retry() }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(HiddenToolbarModifier())
    }
}
