import AVKit
import SwiftUI

struct VideoAttachmentView: View {
    let attachment: Attachment

    @State private var videoPlayer: AVPlayer?
    @State private var isVideoLoading = false

    private let contentWidth: CGFloat = 500
    private let contentHeight: CGFloat = 500

    var body: some View {
        Group {
            if let videoPlayer {
                VideoPlayer(player: videoPlayer)
                    .frame(width: contentWidth, height: contentHeight)
                    .clipShape(.rect(cornerRadius: 12))
                    .onDisappear {
                        stopPlayback(videoPlayer)
                    }
            } else if isVideoLoading {
                ProgressView()
                    .frame(width: contentWidth, height: contentHeight)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                Button {
                    Task {
                        await loadAndPlayVideo()
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(width: contentWidth, height: contentHeight)
                        .background(.background.secondary)
                        .clipShape(.rect(cornerRadius: 12))
                        .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .controlSize(.extraLarge)
            }
        }
    }

    private func loadAndPlayVideo() async {
        if let videoPlayer {
            videoPlayer.play()
            return
        }

        guard let urlString = attachment.resolvedURL else { return }

        isVideoLoading = true
        defer { isVideoLoading = false }

        let ext = attachment.mimeType?.split(separator: "/").last.map(String.init) ?? "mp4"
        guard let fileURL = await AuthenticatedImageLoader.downloadToTempFile(
            urlString: urlString,
            fileExtension: ext
        ) else { return }

        let player = AVPlayer(url: fileURL)
        videoPlayer = player
        player.play()
    }

    private func stopPlayback(_ player: AVPlayer) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        videoPlayer = nil
    }

    private func formattedDuration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
