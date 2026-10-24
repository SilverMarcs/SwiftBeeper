import AVFoundation
import Observation

/// Own the player so the loading indicator covers both downloading and
/// AVFoundation preparation. Actual playback ends the initial loading state.
@MainActor
@Observable
final class AttachmentVideoPlayback {
    let player = AVQueuePlayer()
    private(set) var hasPlayer = false
    private(set) var isReadyForPlayback = false
    private(set) var hasFailed = false

    @ObservationIgnored private var loadingTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var loadedSource: String?
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var currentItemObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playbackObservation: NSKeyValueObservation?

    func load(source: String, muted: Bool) async {
        if loadedSource == source, let loadingTask {
            await loadingTask.value
            return
        }
        if hasPlayer, !hasFailed, loadedSource == source {
            player.play()
            return
        }
        stop()
        loadedSource = source
        let generation = generation
        // The playback owner retains preparation across SwiftUI task restarts.
        // A second request joins it instead of dropping the request or fetching twice.
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.prepare(source: source, muted: muted, generation: generation)
        }
        loadingTask = task
        await task.value
        if self.generation == generation { loadingTask = nil }
    }

    private func prepare(source: String, muted: Bool, generation: UUID) async {
        guard let url = await MatrixMedia.temporaryFile(for: source, fileExtension: "mp4") else {
            if self.generation == generation { hasFailed = true }
            return
        }
        do {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable) else {
                if self.generation == generation { hasFailed = true }
                return
            }
            try Task.checkCancellation()
            guard self.generation == generation else { return }
            player.isMuted = muted
            let item = AVPlayerItem(asset: asset)
            looper = AVPlayerLooper(player: player, templateItem: item)
            currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.observeCurrentItem() }
            }
            playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateReadiness() }
            }
            hasPlayer = true
            player.play()
        } catch is CancellationError {
            // A row that left the viewport can reuse its cached file next time.
        } catch {
            if self.generation == generation { hasFailed = true }
        }
    }

    func stop() {
        generation = UUID()
        loadingTask?.cancel()
        loadingTask = nil
        currentItemObservation = nil
        itemStatusObservation = nil
        playbackObservation = nil
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.removeAllItems()
        hasPlayer = false
        isReadyForPlayback = false
        hasFailed = false
        loadedSource = nil
    }

    private func observeCurrentItem() {
        itemStatusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateReadiness() }
        }
        updateReadiness()
    }

    private func updateReadiness() {
        if player.status == .failed || player.currentItem?.status == .failed {
            hasFailed = true
            isReadyForPlayback = false
        } else if player.currentItem?.status == .readyToPlay, player.timeControlStatus == .playing {
            isReadyForPlayback = true
        }
    }
}
