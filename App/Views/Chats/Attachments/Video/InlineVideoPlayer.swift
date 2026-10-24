import AVKit
import SwiftUI

/// The in-bubble player. macOS uses AppKit's player view, which has its own
/// full-screen toggle; on iOS a tap opens `FullScreenVideoView` instead.
struct InlineVideoPlayer: View {
    let player: AVPlayer
    let openFullScreen: () -> Void

    var body: some View {
        #if os(macOS)
        MacVideoPlayer(player: player)
        #else
        VideoPlayer(player: player)
            .allowsHitTesting(false)
            .overlay {
                Button(action: openFullScreen) {
                    Color.clear
                        .contentShape(.rect)
                        .accessibilityLabel("View Video Full Screen")
                }
                .buttonStyle(.plain)
            }
        #endif
    }
}

#if os(macOS)
private struct MacVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}
#endif
