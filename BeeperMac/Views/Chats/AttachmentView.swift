import AVKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AttachmentView: View {
    @Environment(SessionStore.self) private var sessionStore

    let attachment: Attachment
    let isOutgoing: Bool

    var body: some View {
        if attachment.isImage {
            imageAttachment
        } else if attachment.isVideo {
            videoAttachment
        } else if attachment.isAudio {
            audioAttachment
        } else {
            fileAttachment
        }
    }

    // MARK: - Shared

    private func buildRequest(for urlString: String) -> URLRequest? {
        guard let sourceURL = URL(string: urlString) else { return nil }

        if sourceURL.scheme == "mxc" || sourceURL.scheme == "localmxc" || sourceURL.scheme == "file" {
            guard var components = URLComponents(string: "http://localhost:23373/v1/assets/serve") else {
                return nil
            }
            components.queryItems = [URLQueryItem(name: "url", value: urlString)]
            guard let proxyURL = components.url else { return nil }

            var request = URLRequest(url: proxyURL)
            request.setValue("Bearer \(sessionStore.accessToken)", forHTTPHeaderField: "Authorization")
            return request
        }

        return URLRequest(url: sourceURL)
    }

    /// Downloads data via authenticated request and writes to a temp file, returning its URL.
    private func downloadToTempFile(urlString: String, fileExtension: String) async -> URL? {
        guard let request = buildRequest(for: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = UUID().uuidString + "." + fileExtension
            let fileURL = tempDir.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Image Attachment

    @State private var loadedImage: Image?
    @State private var isLoading = false

    private var imageAttachment: some View {
        Group {
            if let loadedImage {
                loadedImage
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 300, maxHeight: 500)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 12))
            } else if isLoading {
                ProgressView()
                    .frame(width: 150, height: 100)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                    .frame(width: 150, height: 100)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .task(id: "\(attachment.resolvedURL ?? "none")|\(sessionStore.accessToken)") {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let urlString = attachment.resolvedURL, let request = buildRequest(for: urlString) else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }
            loadedImage = makeImage(from: data)
        } catch {}
    }

    private func makeImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }

    // MARK: - Video Attachment

    @State private var videoPlayer: AVPlayer?
    @State private var isVideoLoading = false

    private var videoAttachment: some View {
        Group {
            if let videoPlayer {
                VideoPlayer(player: videoPlayer)
                    .frame(minHeight: 500)
                    .frame(width: 500)
                    .cornerRadius(12)
                    .onDisappear {
                        videoPlayer.replaceCurrentItem(with: nil)
                    }
            } else if isVideoLoading {
                ProgressView()
                    .frame(width: 200, height: 150)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                    .frame(width: 200, height: 150)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .task(id: attachment.resolvedURL) {
            await loadVideo()
        }
    }

    private func loadVideo() async {
        guard let urlString = attachment.resolvedURL else { return }

        isVideoLoading = true
        defer { isVideoLoading = false }

        let ext = attachment.mimeType?.components(separatedBy: "/").last ?? "mp4"
        guard let fileURL = await downloadToTempFile(urlString: urlString, fileExtension: ext) else {
            return
        }

        videoPlayer = AVPlayer(url: fileURL)
    }

    // MARK: - Audio Attachment

    @State private var audioPlayer: AVPlayer?
    @State private var isAudioPlaying = false
    @State private var isAudioLoading = false

    private var audioAttachment: some View {
        Group {
            if audioPlayer != nil {
                Button {
                    toggleAudioPlayback()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isAudioPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.fileName ?? "Audio")
                                .font(.callout)
                                .lineLimit(1)
                            if let duration = attachment.duration {
                                Text(formatDuration(duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if isAudioLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(attachment.fileName ?? "Audio")
                        .font(.callout)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isOutgoing ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.background.tertiary))
        .clipShape(.rect(cornerRadius: 12))
        .task(id: attachment.resolvedURL) {
            await loadAudio()
        }
    }

    private func loadAudio() async {
        guard let urlString = attachment.resolvedURL else { return }

        isAudioLoading = true
        defer { isAudioLoading = false }

        let ext = attachment.mimeType?.components(separatedBy: "/").last ?? "m4a"
        guard let fileURL = await downloadToTempFile(urlString: urlString, fileExtension: ext) else {
            return
        }
        let player = AVPlayer(url: fileURL)
        audioPlayer = player

        // Observe when playback finishes
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            isAudioPlaying = false
            player.seek(to: .zero)
        }
    }

    private func toggleAudioPlayback() {
        guard let player = audioPlayer else { return }
        if isAudioPlaying {
            player.pause()
        } else {
            player.play()
        }
        isAudioPlaying.toggle()
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - File Attachment

    private var fileAttachment: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName ?? "Attachment")
                    .font(.callout)
                    .lineLimit(1)

                if let fileSize = attachment.fileSize {
                    Text(formattedFileSize(fileSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isOutgoing ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.background.tertiary))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func formattedFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
