import AVKit
import SwiftUI

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
