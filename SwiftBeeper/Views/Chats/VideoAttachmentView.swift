import AVKit
import SwiftUI

struct VideoAttachmentView: View {
    @Environment(SessionStore.self) private var sessionStore

    let attachment: Attachment

    @State private var videoPlayer: AVPlayer?
    @State private var isVideoLoading = false

    var body: some View {
        Group {
            if let videoPlayer {
                VideoPlayer(player: videoPlayer)
                    .frame(width: 500, height: 500)
                    .cornerRadius(12)
                    .onDisappear {
                        videoPlayer.replaceCurrentItem(with: nil)
                    }
            } else if isVideoLoading {
                ProgressView()
                    .frame(width: 200, height: 150)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                    .frame(width: 200, height: 150)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .task(id: attachment.resolvedURL) {
            await loadVideo()
        }
    }

    private func loadVideo() async {
        guard let urlString = attachment.resolvedURL else { return }

        isVideoLoading = true
        defer { isVideoLoading = false }

        let ext = attachment.mimeType?.components(separatedBy: "/").last ?? "mp4"
        guard let fileURL = await AuthenticatedImageLoader.downloadToTempFile(
            urlString: urlString,
            accessToken: sessionStore.accessToken,
            fileExtension: ext
        ) else { return }

        videoPlayer = AVPlayer(url: fileURL)
    }
}
