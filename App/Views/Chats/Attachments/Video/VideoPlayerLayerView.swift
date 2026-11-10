#if os(iOS)
import AVFoundation
import SwiftUI

/// The inline video bubble's picture: a bare `AVPlayerLayer` without
/// controls, aspect-fit inside the bubble.
struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerHostView, context: Context) {
        view.playerLayer.player = player
    }
}
#endif
