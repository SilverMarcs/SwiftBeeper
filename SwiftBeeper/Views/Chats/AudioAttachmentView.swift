import AVKit
import OSLog
import SwiftOGG
import SwiftUI

private let logger = Logger(subsystem: "SwiftBeeper", category: "AudioAttachment")

struct AudioAttachmentView: View {
    let attachment: Attachment
    let isOutgoing: Bool

    @State private var audioPlayer: AVPlayer?
    @State private var playbackObserver: NSObjectProtocol?
    @State private var isAudioPlaying = false
    @State private var isAudioLoading = false
    @State private var loadError: String?

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
                    Image(systemName: loadError != nil ? "exclamationmark.triangle" : "waveform")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(attachment.fileName ?? "Audio")
                        .font(.callout)
                        .lineLimit(1)
                }
                .onTapGesture {
                    Task { await loadAudio() }
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
        guard let urlString = attachment.resolvedURL else {
            logger.warning("Audio attachment has no resolved URL")
            loadError = "No URL"
            return
        }

        isAudioLoading = true
        loadError = nil
        defer { isAudioLoading = false }

        let ext = Self.fileExtension(from: attachment.mimeType)
        guard let fileURL = await AuthenticatedImageLoader.downloadToTempFile(
            urlString: urlString,
            fileExtension: ext
        ) else {
            logger.error("Failed to download audio: \(urlString)")
            loadError = "Download failed"
            return
        }

        let playableURL: URL
        if Self.isOggOpus(mimeType: attachment.mimeType, fileExtension: ext) {
            let m4aURL = fileURL.deletingPathExtension().appendingPathExtension("m4a")
            do {
                try OGGConverter.convertOpusOGGToM4aFile(src: fileURL, dest: m4aURL)
                playableURL = m4aURL
                logger.info("Converted OGG Opus to M4A")
            } catch {
                logger.error("OGG to M4A conversion failed: \(error)")
                loadError = "Unsupported format"
                return
            }
        } else {
            playableURL = fileURL
        }

        let playerItem = AVPlayerItem(url: playableURL)
        let player = AVPlayer(playerItem: playerItem)

        // Wait for the player item to be ready (or fail)
        let isPlayable = (try? await playerItem.asset.load(.isPlayable)) ?? false
        guard isPlayable else {
            logger.error("AVPlayer cannot play this audio format: \(attachment.mimeType ?? "unknown")")
            loadError = "Unsupported format"
            return
        }

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

    /// Extract a clean file extension from a MIME type like "audio/ogg; codecs=opus"
    static func fileExtension(from mimeType: String?) -> String {
        guard let mimeType else { return "m4a" }
        // Strip parameters (e.g. "; codecs=opus")
        let base = mimeType.components(separatedBy: ";").first ?? mimeType
        let subtype = base.components(separatedBy: "/").last?.trimmingCharacters(in: .whitespaces) ?? "m4a"
        // Map common subtypes to proper extensions
        switch subtype {
        case "mpeg": return "mp3"
        case "mp4", "x-m4a", "m4a": return "m4a"
        case "ogg", "opus": return "ogg"
        case "x-wav", "wav": return "wav"
        case "aac": return "aac"
        case "x-caf", "x-aiff": return "caf"
        default: return subtype
        }
    }

    static func isOggOpus(mimeType: String?, fileExtension: String) -> Bool {
        let mime = (mimeType ?? "").lowercased()
        return fileExtension == "ogg"
            || mime.contains("ogg")
            || mime.contains("opus")
    }
}
