import AVFoundation
import Observation

/// Owns one video bubble's looping player, so the loading indicator covers
/// both the download and AVFoundation's preparation. Actual playback (not
/// just a ready item) ends the initial loading state.
@MainActor
@Observable
final class AttachmentVideoPlayback {
    let player = AVQueuePlayer()
    private(set) var hasPlayer = false
    private(set) var isReadyForPlayback = false
    private(set) var hasFailed = false

    @ObservationIgnored private var loadingTask: Task<Void, Never>?
    /// Bumped by `stop()` so a superseded preparation can't touch the player.
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var loadedSource: String?
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var currentItemObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playbackObservation: NSKeyValueObservation?

    func load(source: String, muted: Bool) async {
        // The preparation task outlives SwiftUI task restarts; a repeat
        // request joins it instead of dropping the request or fetching twice.
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
        let task = Task<Void, Never> { [weak self] in
            await self?.prepare(source: source, muted: muted, generation: generation)
        }
        loadingTask = task
        await task.value
        if self.generation == generation { loadingTask = nil }
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

    private func prepare(source: String, muted: Bool, generation: UUID) async {
        guard let url = await MatrixMedia.temporaryFile(for: source, fileExtension: "mp4") else {
            fail(generation)
            return
        }
        do {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable) else {
                fail(generation)
                return
            }
            try Task.checkCancellation()
            guard self.generation == generation else { return }
            player.isMuted = muted
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
            // The looper swaps items, so follow each new item's status.
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
            fail(generation)
        }
    }

    private func fail(_ generation: UUID) {
        if self.generation == generation { hasFailed = true }
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
