import AVKit
import OSLog
import SwiftOGG
import SwiftUI

private let logger = Logger(subsystem: "Relay", category: "AudioAttachment")

struct AudioAttachmentView: View {
    let attachment: Attachment
    let message: Message
    let chat: Chat

    @Environment(AudioPlayerService.self) private var playerService

    @State private var localIsLoading = false
    @State private var isSeeking = false
    @State private var localCurrentTime: Double = 0
    @State private var localDuration: Double?

    private var isCurrent: Bool {
        attachment.resolvedURL != nil && attachment.resolvedURL == playerService.currentAttachmentURL
    }
    
    private var isReady: Bool {
        isCurrent && !playerService.isAudioLoading
    }

    private var isAudioPlaying: Bool {
        isCurrent && playerService.isAudioPlaying
    }

    private var isAudioLoading: Bool {
        (isCurrent && playerService.isAudioLoading) || localIsLoading
    }

    private var currentTime: Double {
        if isSeeking { return localCurrentTime }
        return isCurrent ? playerService.currentTime : 0
    }
    
    private var duration: Double {
        if isCurrent && playerService.duration > 0 { return playerService.duration }
        if let ld = localDuration { return ld }
        return attachment.duration ?? 0
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { self.currentTime },
            set: { self.localCurrentTime = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if isReady {
                    playerService.toggleAudioPlayback()
                } else if !isAudioLoading {
                    Task { await loadAudio() }
                }
            } label: {
                Image(systemName: isAudioPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Slider(
                value: sliderValue,
                in: 0...max(duration, 1)
            ) { editing in
                isSeeking = editing
                if !editing {
                    if isCurrent {
                        playerService.seek(to: localCurrentTime)
                    }
                }
            }
            .frame(width: 160)
            .disabled(!isReady)

            Text(formatDuration(isSeeking || isAudioPlaying ? currentTime : duration))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .opacity(isAudioLoading ? 0.4 : 1.0)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .bubbleBackground(isOutgoing: message.isSender)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func loadAudio() async {
        guard let urlString = attachment.resolvedURL else {
            logger.warning("Audio attachment has no resolved URL")
            return
        }

        localIsLoading = true
        defer { localIsLoading = false }

        let ext = Self.fileExtension(from: attachment.mimeType)
        guard let fileURL = await MatrixMedia.temporaryFile(for: urlString, fileExtension: ext) else {
            logger.error("Failed to download audio: \(urlString)")
            return
        }

        let playableURL: URL
        if Self.isOggOpus(mimeType: attachment.mimeType, fileExtension: ext) {
            let m4aURL = fileURL.deletingPathExtension().appendingPathExtension("m4a")
            // A previous play may have converted this file already.
            if !FileManager.default.fileExists(atPath: m4aURL.path) {
                do {
                    // CPU-bound transcode; the view is MainActor-isolated (project
                    // default), so hop off the main thread to keep the UI responsive.
                    try await Task.detached(priority: .userInitiated) {
                        try OGGConverter.convertOpusOGGToM4aFile(src: fileURL, dest: m4aURL)
                    }.value
                } catch {
                    // Don't leave a partial file for the next play to reuse.
                    try? FileManager.default.removeItem(at: m4aURL)
                    logger.error("OGG to M4A conversion failed: \(error)")
                    return
                }
            }
            playableURL = m4aURL
        } else {
            playableURL = fileURL
        }

        // Wait to get actual duration if possible
        let playerItem = AVPlayerItem(url: playableURL)
        if let itemDuration = try? await playerItem.asset.load(.duration), itemDuration.isNumeric {
            localDuration = itemDuration.seconds
        }

        await playerService.play(
            attachmentURL: urlString,
            playableURL: playableURL,
            givenDuration: attachment.duration,
            // Now Playing names the other side of the conversation.
            title: message.isSender ? chat.displayTitle : message.senderDisplayName,
            avatarURL: message.isSender ? chat.imgURL : chat.participant(with: message.senderID)?.imgURL
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
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
