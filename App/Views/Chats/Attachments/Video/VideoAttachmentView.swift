import SwiftMediaViewer
import SwiftUI

/// An inline, looping video bubble. Videos load once they're on screen and
/// either autoplay is on or the user taps Play. Reels first need the core to
/// resolve their media, which `ChatStore` limits to two at a time.
struct VideoAttachmentView: View {
    let attachment: Attachment
    let message: Message

    @Environment(ChatStore.self) private var chatStore
    @AppStorage("autoplay") private var autoplay = true
    @AppStorage("muteOnPlay") private var muteOnPlay = false
    #if os(macOS)
    @State private var playback = AttachmentVideoPlayback()
    #else
    @State private var playbackURL: URL?
    @State private var downloadFailed = false
    #endif
    @State private var userRequestedPlay = false
    @State private var hasRequestedResolution = false
    @State private var isVisible = false

    var body: some View {
        let size = MediaBubbleSize.fitting(attachment.size)
        ZStack {
            #if os(macOS)
            if playback.hasPlayer {
                MacVideoPlayer(player: playback.player)
            }
            #else
            if let playbackURL {
                SMVVideo(videoURL: playbackURL.absoluteString, autoplay: true, muteOnPlay: muteOnPlay)
            }
            #endif
            if !isReadyForPlayback {
                VideoAttachmentPoster(source: attachment.type == .reel ? attachment.resolvedURL : attachment.posterImg)
                    .overlay {
                        if chatStore.failedMediaIDs.contains(message.id) {
                            Button("Retry Reel", systemImage: "arrow.clockwise") {
                                userRequestedPlay = true
                                hasRequestedResolution = true
                                Task { await chatStore.resolveMedia(message, retry: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(chatStore.resolvingMediaIDs.count >= ChatStore.maxConcurrentMediaResolves)
                        } else if hasFailed {
                            Button("Retry Video", systemImage: "arrow.clockwise") {
                                Task { await loadVideo() }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            VideoPlaybackControl(isLoading: shouldPlay) {
                                userRequestedPlay = true
                            }
                        }
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 12))
        .onScrollVisibilityChange(threshold: 0.25) { isVisible = $0 }
        .task(id: loadRequest) {
            guard let request = loadRequest else { return }
            // A Play tap has already expressed intent. Autoplay waits briefly
            // so passing a video while scrolling need not download it.
            if !hasRequestedResolution && !userRequestedPlay {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            switch request {
            case .resolve:
                hasRequestedResolution = true
                await chatStore.resolveMedia(message)
            case .play:
                await loadVideo()
            }
        }
        #if os(macOS)
        .onDisappear { playback.stop() }
        #endif
    }

    private var isReadyForPlayback: Bool {
        #if os(macOS)
        playback.isReadyForPlayback
        #else
        playbackURL != nil
        #endif
    }

    private var hasFailed: Bool {
        #if os(macOS)
        playback.hasFailed
        #else
        downloadFailed
        #endif
    }

    private var shouldPlay: Bool { autoplay || userRequestedPlay }

    private var loadRequest: LoadRequest? {
        guard shouldPlay, isVisible else { return nil }
        if attachment.type == .reel {
            guard !chatStore.failedMediaIDs.contains(message.id),
                  chatStore.resolvingMediaIDs.contains(message.id) || chatStore.resolvingMediaIDs.count < ChatStore.maxConcurrentMediaResolves else {
                return nil
            }
            return .resolve(message.id)
        }
        return attachment.resolvedURL.map { .play($0) }
    }

    private func loadVideo() async {
        guard let source = attachment.resolvedURL else { return }
        #if os(macOS)
        await playback.load(source: source, muted: muteOnPlay)
        #else
        downloadFailed = false
        let url = await MatrixMedia.temporaryFile(for: source, fileExtension: "mp4")
        guard !Task.isCancelled else { return }
        playbackURL = url
        downloadFailed = url == nil
        #endif
    }
}

/// The `.task` id. Changing from a reel placeholder to its resolved video
/// restarts the task while keeping the view's Play intent and its continuous
/// loading indicator.
private enum LoadRequest: Hashable {
    case resolve(String)
    case play(String)
}
