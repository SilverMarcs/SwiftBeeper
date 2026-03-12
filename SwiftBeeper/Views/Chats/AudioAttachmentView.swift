import AVKit
import SwiftUI

struct AudioAttachmentView: View {
    let attachment: Attachment
    let isOutgoing: Bool

    @State private var audioPlayer: AVPlayer?
    @State private var playbackObserver: NSObjectProtocol?
    @State private var isAudioPlaying = false
    @State private var isAudioLoading = false

    var body: some View {
        Group {
            if audioPlayer != nil {
                Button {
                    toggleAudioPlayback()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isAudioPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.fileName ?? "Audio")
                                .font(.callout)
                                .lineLimit(1)
                            if let duration = attachment.duration {
                                Text(formatDuration(duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if isAudioLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(attachment.fileName ?? "Audio")
                        .font(.callout)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ChatVisualStyle.bubbleFill(isOutgoing: isOutgoing))
        .clipShape(.rect(cornerRadius: 12))
        .task(id: attachment.resolvedURL) {
            await loadAudio()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func loadAudio() async {
        guard let urlString = attachment.resolvedURL else { return }

        isAudioLoading = true
        defer { isAudioLoading = false }

        let ext = attachment.mimeType?.components(separatedBy: "/").last ?? "m4a"
        guard let fileURL = await AuthenticatedImageLoader.downloadToTempFile(
            urlString: urlString,
            fileExtension: ext
        ) else { return }

        let player = AVPlayer(url: fileURL)
        audioPlayer = player

        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            isAudioPlaying = false
            player.seek(to: .zero)
        }
    }

    private func toggleAudioPlayback() {
        guard let player = audioPlayer else { return }
        if isAudioPlaying {
            player.pause()
        } else {
            player.play()
        }
        isAudioPlaying.toggle()
    }

    private func formatDuration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    private func tearDownPlayer() {
        audioPlayer?.pause()
        audioPlayer = nil
        if let playbackObserver {
            NotificationCenter.default.removeObserver(playbackObserver)
            self.playbackObserver = nil
        }
        isAudioPlaying = false
    }
}
