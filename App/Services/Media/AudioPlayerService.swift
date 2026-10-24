import AVFoundation
import Observation
import OSLog
#if os(iOS)
import MediaPlayer
import UIKit
#endif

private let logger = Logger(subsystem: "Relay", category: "AudioPlayerService")

/// Plays one audio attachment at a time, app-wide, and on iOS publishes it to
/// Now Playing and the remote command center.
@MainActor
@Observable
final class AudioPlayerService {
    private static let defaultTitle = "Voice Message"

    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    private var playbackObserver: NSObjectProtocol?

    /// The attachment source (not the playable file) of the loaded audio.
    var currentAttachmentURL: String?
    var isAudioPlaying = false
    var isAudioLoading = false
    var currentTime: Double = 0
    var duration: Double = 0
    var currentTitle = defaultTitle
    #if os(iOS)
    var currentArtwork: MPMediaItemArtwork?
    #endif

    init() {
        setupRemoteCommands()
    }

    /// Loads and plays `playableURL`, or toggles playback if `attachmentURL`
    /// is already loaded.
    func play(attachmentURL: String, playableURL: URL, givenDuration: Double?, title: String? = nil, avatarURL: String? = nil) async {
        if currentAttachmentURL == attachmentURL {
            toggleAudioPlayback()
            return
        }

        tearDownPlayer()

        currentAttachmentURL = attachmentURL
        currentTitle = title ?? Self.defaultTitle
        #if os(iOS)
        currentArtwork = nil
        if let avatarURL {
            Task {
                guard let file = await MatrixMedia.localFile(for: avatarURL),
                      let image = UIImage(contentsOfFile: file.path),
                      // Another attachment may have started while the avatar loaded.
                      currentAttachmentURL == attachmentURL else { return }
                currentArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                updateNowPlayingInfo()
            }
        }
        #endif

        isAudioLoading = true
        defer { isAudioLoading = false }

        setupAudioSession()

        let playerItem = AVPlayerItem(url: playableURL)
        let player = AVPlayer(playerItem: playerItem)

        guard (try? await playerItem.asset.load(.isPlayable)) == true else {
            logger.error("AVPlayer cannot play this audio format")
            // Release the attachment so the next tap can try again.
            tearDownPlayer()
            return
        }

        audioPlayer = player

        if let itemDuration = try? await playerItem.asset.load(.duration), itemDuration.isNumeric {
            duration = itemDuration.seconds
        } else {
            duration = givenDuration ?? 0
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                self.updateNowPlayingInfo()
            }
        }

        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAudioPlaying = false
                self.currentTime = 0
                self.audioPlayer?.seek(to: .zero)
                self.updateNowPlayingInfo()
            }
        }

        player.play()
        isAudioPlaying = true
        updateNowPlayingInfo()
    }

    func toggleAudioPlayback() {
        guard let player = audioPlayer else { return }
        if isAudioPlaying {
            player.pause()
        } else {
            setupAudioSession()
            player.play()
        }
        isAudioPlaying.toggle()
        updateNowPlayingInfo()
    }

    func seek(to time: Double) {
        currentTime = time
        audioPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        updateNowPlayingInfo()
    }

    private func tearDownPlayer() {
        if let timeObserver {
            audioPlayer?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        audioPlayer?.pause()
        audioPlayer = nil
        if let playbackObserver {
            NotificationCenter.default.removeObserver(playbackObserver)
            self.playbackObserver = nil
        }
        isAudioPlaying = false
        currentTime = 0
        currentAttachmentURL = nil
        currentTitle = Self.defaultTitle
    }

    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Failed to set audio session category: \(error.localizedDescription)")
        }
        #endif
    }

    private func setupRemoteCommands() {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self, !isAudioPlaying else { return .commandFailed }
            Task { @MainActor in self.toggleAudioPlayback() }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self, isAudioPlaying else { return .commandFailed }
            Task { @MainActor in self.toggleAudioPlayback() }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self.seek(to: positionEvent.positionTime) }
            return .success
        }
        #endif
    }

    private func updateNowPlayingInfo() {
        #if os(iOS)
        guard audioPlayer != nil else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyArtist: "Relay",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isAudioPlaying ? 1.0 : 0.0
        ]
        if let currentArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = currentArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        #endif
    }
}
