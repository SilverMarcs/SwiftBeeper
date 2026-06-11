import SwiftMediaViewer
import SwiftUI

struct VideoAttachmentView: View {
    let attachment: Attachment

    @AppStorage("autoplay") private var autoplay = true
    @AppStorage("muteOnPlay") private var muteOnPlay = false

    @State private var showVideo = false

    private let maxWidth: CGFloat = Device.isMacOrPad ? 400 : 275
    private let maxHeight: CGFloat = 500

    var body: some View {
        Group {
            if showVideo, let urlString = AuthenticatedImageLoader.displayURL(for: attachment.resolvedURL)?.absoluteString {
                // SMVVideo shows an inline player and zooms to a full-screen
                // AVPlayer on tap; autoplay it since we only reach here once the
                // poster has been swapped out (by tap or the autoplay delay).
                SMVVideo(videoURL: urlString, autoplay: true, muteOnPlay: muteOnPlay)
            } else {
                preview
            }
        }
        .frame(width: videoSize.width, height: videoSize.height)
        .clipShape(.rect(cornerRadius: 12))
    }

    // Poster + play button. With autoplay on, this shows for ~1s then hands off
    // to SMVVideo — so videos don't all start fetching at once while scrolling.
    private var preview: some View {
        Button {
            showVideo = true
        } label: {
            posterImage
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .padding()
                        .background(.black.opacity(0.5), in: .circle)
                        .foregroundStyle(.white)
                }
        }
        .buttonStyle(.plain)
        .task {
            guard autoplay else { return }
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            showVideo = true
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let posterURL = AuthenticatedImageLoader.displayURL(for: attachment.posterImg) {
            CachedAsyncImage(url: posterURL, targetSize: 450) {
                Color.clear.subtleBackground()
            }
            .scaledToFill()
        } else {
            Color.clear.subtleBackground()
        }
    }

    private var videoSize: CGSize {
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
