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
        } else {
            fileAttachment
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
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 300)
                    .clipShape(.rect(cornerRadius: 12))
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: imageFrameWidth, height: imageFrameHeight)
                    .overlay {
                        ProgressView()
                    }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: imageFrameWidth, height: imageFrameHeight)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .font(.title2)
                    }
            }
        }
        .task(id: imageRequestKey) {
            await loadImage()
        }
    }

    private var imageFrameWidth: CGFloat {
        if let size = attachment.size, let w = size.width, w > 0 {
            return min(300, CGFloat(w)).rounded()
        }
        return 200
    }

    private var imageFrameHeight: CGFloat {
        if let size = attachment.size, let w = size.width, let h = size.height, w > 0, h > 0 {
            let displayWidth = min(300, CGFloat(w))
            let aspect = CGFloat(w) / CGFloat(h)
            return (displayWidth / aspect).rounded()
        }
        return 150
    }

    private var imageRequestKey: String {
        "\(attachment.resolvedURL ?? "none")|\(sessionStore.accessToken)"
    }

    private func loadImage() async {
        guard let request = imageRequest else {
            loadedImage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                loadedImage = nil
                return
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                loadedImage = nil
                return
            }

            loadedImage = makeImage(from: data)
        } catch {
            loadedImage = nil
        }
    }

    private var imageRequest: URLRequest? {
        guard let urlString = attachment.resolvedURL, urlString.isEmpty == false else {
            return nil
        }

        guard let sourceURL = URL(string: urlString) else {
            return nil
        }

        if sourceURL.scheme == "mxc" || sourceURL.scheme == "localmxc" || sourceURL.scheme == "file" {
            guard var components = URLComponents(string: "http://localhost:23373/v1/assets/serve") else {
                return nil
            }
            components.queryItems = [
                URLQueryItem(name: "url", value: urlString)
            ]
            guard let proxyURL = components.url else {
                return nil
            }

            var request = URLRequest(url: proxyURL)
            request.setValue("Bearer \(sessionStore.accessToken)", forHTTPHeaderField: "Authorization")
            return request
        }

        return URLRequest(url: sourceURL)
    }

    private func makeImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else {
            return nil
        }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: data) else {
            return nil
        }
        return Image(uiImage: uiImage)
        #endif
    }

    // MARK: - File Attachment

    private var fileAttachment: some View {
        HStack(spacing: 8) {
            Image(systemName: fileIconName)
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
        .background(isOutgoing ? Color.accentColor.opacity(0.20) : Color.gray.opacity(0.15))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var fileIconName: String {
        if attachment.isVideo { return "film" }
        if attachment.isAudio { return "waveform" }
        return "doc"
    }

    private func formattedFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
