import AVKit
import SwiftUI

struct VideoAttachmentView: View {
    let attachment: Attachment

    @State private var videoPlayer: AVPlayer?
    @State private var isLoading = false

    private let maxWidth: CGFloat = 500
    private let maxHeight: CGFloat = 500

    var body: some View {
        Group {
            if let videoPlayer {
                VideoPlayer(player: videoPlayer)
                    .frame(width: videoSize.width, height: videoSize.height)
                    .clipShape(.rect(cornerRadius: 12))
                    .onDisappear {
                        stopPlayback(videoPlayer)
                    }
            } else if isLoading {
                ProgressView()
                    .frame(width: videoSize.width, height: videoSize.height)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                Color.clear
                    .frame(width: videoSize.width, height: videoSize.height)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .task(id: attachment.resolvedURL) {
            await loadVideo()
        }
    }

    private var videoSize: CGSize {
        guard let w = attachment.size?.width, let h = attachment.size?.height,
              w > 0, h > 0 else {
            return CGSize(width: maxWidth, height: maxWidth)
        }

        let aspectRatio = CGFloat(w) / CGFloat(h)
        var width = min(CGFloat(w), maxWidth)
        var height = width / aspectRatio

        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        return CGSize(width: width, height: height)
    }

    private func loadVideo() async {
        guard let urlString = attachment.resolvedURL else { return }

        isLoading = true
        defer { isLoading = false }

        let ext = attachment.mimeType?.split(separator: "/").last.map(String.init) ?? "mp4"
        guard let fileURL = await AuthenticatedImageLoader.downloadToTempFile(
            urlString: urlString,
            fileExtension: ext
        ) else { return }

        let player = AVPlayer(url: fileURL)
        player.pause()
        videoPlayer = player
    }

    private func stopPlayback(_ player: AVPlayer) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        videoPlayer = nil
    }
}
