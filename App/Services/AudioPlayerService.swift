import Foundation
import AVFoundation
import AVKit
import Observation
import OSLog
#if os(iOS)
import MediaPlayer
import UIKit
#endif

private let logger = Logger(subsystem: "Relay", category: "AudioPlayerService")

@MainActor
@Observable
final class AudioPlayerService {
    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    private var playbackObserver: NSObjectProtocol?

    var currentAttachmentURL: String?
    var isAudioPlaying = false
    var isAudioLoading = false
    var currentTime: Double = 0
    var duration: Double = 0
    var currentTitle: String = "Voice Message"
#if os(iOS)
    var currentArtwork: MPMediaItemArtwork?
#endif
    
    init() {
        setupRemoteCommands()
    }

    func play(attachmentURL: String, playableURL: URL, givenDuration: Double?, title: String? = nil, avatarURL: String? = nil) async {
        if currentAttachmentURL == attachmentURL {
            // Already loaded this one, just toggle
            toggleAudioPlayback()
            return
        }

        tearDownPlayer()

        currentAttachmentURL = attachmentURL
        currentTitle = title ?? "Voice Message"
#if os(iOS)
        currentArtwork = nil
        if let avatarURL {
            Task {
                guard let file = await MatrixMedia.localFile(for: avatarURL),
                      let image = UIImage(contentsOfFile: file.path) else { return }
                currentArtwork = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ in image })
                updateNowPlayingInfo()
            }
        }
#endif

        isAudioLoading = true
        defer { isAudioLoading = false }

        setupAudioSession()

        let playerItem = AVPlayerItem(url: playableURL)
        let player = AVPlayer(playerItem: playerItem)

        let isPlayable = (try? await playerItem.asset.load(.isPlayable)) ?? false
        guard isPlayable else {
            logger.error("AVPlayer cannot play this audio format")
            return
        }

        audioPlayer = player

        let itemDuration = try? await playerItem.asset.load(.duration)
        if let itemDuration, itemDuration.isNumeric {
            duration = itemDuration.seconds
        } else if let d = givenDuration {
            duration = d
        } else {
            duration = 0
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
            object: player.currentItem,
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
        if let player = audioPlayer {
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        }
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
        currentTitle = "Voice Message"
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
            guard let self = self else { return .commandFailed }
            if !self.isAudioPlaying {
                Task { @MainActor in
                    self.toggleAudioPlayback()
                }
                return .success
            }
            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isAudioPlaying {
                Task { @MainActor in
                    self.toggleAudioPlayback()
                }
                return .success
            }
            return .commandFailed
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self.seek(to: positionEvent.positionTime)
            }
            return .success
        }
        #endif
    }

    private func updateNowPlayingInfo() {
        #if os(iOS)
        guard let _ = audioPlayer else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Relay"
        
        if let artwork = currentArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isAudioPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        #endif
    }
}
