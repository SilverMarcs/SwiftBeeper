import AVKit
import SwiftUI

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
                            .disabled(chatStore.resolvingMediaIDs.count >= 2)
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
        .frame(width: videoSize.width, height: videoSize.height)
        .clipShape(.rect(cornerRadius: 12))
        .onScrollVisibilityChange(threshold: 0.25) { isVisible = $0 }
        .task(id: loadRequest) {
            guard let request = loadRequest else { return }
            do {
                // A Play tap has already expressed intent. Autoplay waits briefly
                // so passing a video while scrolling need not download it.
                if !hasRequestedResolution && !userRequestedPlay {
                    try await Task.sleep(for: .seconds(1))
                }
                try Task.checkCancellation()
                switch request {
                case .resolve:
                    hasRequestedResolution = true
                    await chatStore.resolveMedia(message)
                case .play:
                    await loadVideo()
                }
            } catch { }
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

    private var loadRequest: VideoAttachmentRequest? {
        guard shouldPlay, isVisible else { return nil }
        if attachment.type == .reel {
            guard !chatStore.failedMediaIDs.contains(message.id),
                  chatStore.resolvingMediaIDs.contains(message.id) || chatStore.resolvingMediaIDs.count < 2 else {
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

    private var videoSize: CGSize {
        let maxWidth: CGFloat = Device.isMacOrPad ? 400 : 275
        let maxHeight: CGFloat = 500
        guard let w = attachment.size?.width, let h = attachment.size?.height,
              w > 0, h > 0 else {
            return CGSize(width: maxWidth, height: maxWidth)
        }
        let aspectRatio = CGFloat(w) / CGFloat(h)
        var width = min(CGFloat(w), maxWidth)
        var height = width / aspectRatio
        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }
        return CGSize(width: width, height: height)
    }
}
