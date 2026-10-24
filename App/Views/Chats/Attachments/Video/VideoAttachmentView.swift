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
    @State private var playback = AttachmentVideoPlayback()
    @State private var userRequestedPlay = false
    @State private var hasRequestedResolution = false
    @State private var isVisible = false
    @State private var showFullScreen = false

    var body: some View {
        let size = MediaBubbleSize.fitting(attachment.size)
        ZStack {
            if playback.hasPlayer {
                InlineVideoPlayer(player: playback.player) { showFullScreen = true }
            }
            if !playback.isReadyForPlayback {
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
                        } else if playback.hasFailed {
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
        .onDisappear {
            if !showFullScreen { playback.stop() }
        }
        #if !os(macOS)
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenVideoView(player: playback.player)
        }
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
        await playback.load(source: source, muted: muteOnPlay)
    }
}

/// The `.task` id. Changing from a reel placeholder to its resolved video
/// restarts the task while keeping the view's Play intent and its continuous
/// loading indicator.
private enum LoadRequest: Hashable {
    case resolve(String)
    case play(String)
}
