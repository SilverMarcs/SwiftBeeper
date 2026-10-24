import SwiftUI

/// The Play symbol always determines layout. Loading overlays it, so both
/// states share the same material circle and adapt together to Dynamic Type.
struct VideoPlaybackControl: View {
    let isLoading: Bool
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            Label("Play Video", systemImage: "play.fill")
                .labelStyle(.iconOnly)
                .font(.title2)
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
                .padding()
                .background(.regularMaterial, in: .circle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? Text("Loading video") : Text("Play Video"))
    }
}
