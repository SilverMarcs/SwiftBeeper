import AVKit
import SwiftUI

#if !os(macOS)
struct FullScreenVideoView: View {
    let player: AVPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button("Close Video", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .padding()
            }
    }
}
#endif
