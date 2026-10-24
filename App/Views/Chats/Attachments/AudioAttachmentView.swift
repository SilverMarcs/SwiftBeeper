import SwiftUI

/// A voice message or audio file with play/pause and a scrubber. Playback
/// goes through the shared `AudioPlayerService`, so only one plays at a time.
struct AudioAttachmentView: View {
    let attachment: Attachment
    let message: Message
    let chat: Chat

    @Environment(AudioPlayerService.self) private var playerService

    @State private var isPreparing = false
    @State private var isSeeking = false
    @State private var seekTime: Double = 0
    /// The file's real duration, read when it was prepared.
    @State private var fileDuration: Double?

    private var isCurrent: Bool {
        attachment.resolvedURL != nil && attachment.resolvedURL == playerService.currentAttachmentURL
    }

    private var isReady: Bool {
        isCurrent && !playerService.isAudioLoading
    }

    private var isPlaying: Bool {
        isCurrent && playerService.isAudioPlaying
    }

    private var isLoading: Bool {
        (isCurrent && playerService.isAudioLoading) || isPreparing
    }

    private var currentTime: Double {
        if isSeeking { return seekTime }
        return isCurrent ? playerService.currentTime : 0
    }

    private var duration: Double {
        if isCurrent && playerService.duration > 0 { return playerService.duration }
        return fileDuration ?? attachment.duration ?? 0
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if isReady {
                    playerService.toggleAudioPlayback()
                } else if !isLoading {
                    Task { await loadAudio() }
                }
            } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(get: { currentTime }, set: { seekTime = $0 }),
                in: 0...max(duration, 1)
            ) { editing in
                isSeeking = editing
                if !editing, isCurrent {
                    playerService.seek(to: seekTime)
                }
            }
            .frame(width: 160)
            .disabled(!isReady)

            Text(Duration.seconds(isSeeking || isPlaying ? currentTime : duration), format: .time(pattern: .minuteSecond))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .opacity(isLoading ? 0.4 : 1.0)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .bubbleBackground(isOutgoing: message.isSender)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func loadAudio() async {
        guard let source = attachment.resolvedURL else { return }

        isPreparing = true
        defer { isPreparing = false }

        guard let playableURL = await AudioAttachmentPreparer.playableFile(
            for: source,
            mimeType: attachment.mimeType
        ) else { return }
        if let duration = await AudioAttachmentPreparer.duration(of: playableURL) {
            fileDuration = duration
        }

        await playerService.play(
            attachmentURL: source,
            playableURL: playableURL,
            givenDuration: attachment.duration,
            // Now Playing names the other side of the conversation.
            title: message.isSender ? chat.displayTitle : message.senderDisplayName,
            avatarURL: message.isSender ? chat.imgURL : chat.participant(with: message.senderID)?.imgURL
        )
    }
}
