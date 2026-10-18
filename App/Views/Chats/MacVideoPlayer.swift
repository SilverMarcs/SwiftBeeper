import SwiftUI
import AVKit

#if os(macOS)
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

struct MacVideoPlayer: View {
    let urlString: String
    let autoplay: Bool
    let muteOnPlay: Bool
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player = player {
                AVPlayerViewRepresentable(player: player)
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard let url = URL(string: urlString) else { return }
            let newPlayer = AVPlayer(url: url)
            newPlayer.isMuted = muteOnPlay
            self.player = newPlayer
            if autoplay {
                newPlayer.play()
            }
        }
    }
}
#endif
