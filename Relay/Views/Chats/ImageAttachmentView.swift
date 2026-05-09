import QuickLook
import SwiftUI

struct ImageAttachmentView: View {
    let attachment: Attachment

    @State private var loadedImage: Image?
    @State private var isLoading = false
    @State private var previewURL: URL?

    private let maxWidth: CGFloat = 330
    private let maxHeight: CGFloat = 500

    var body: some View {
        Button {
            if loadedImage != nil {
                Task { await openQuickLook() }
            }
        } label: {
            ZStack {
                Color.clear

                if let loadedImage {
                    loadedImage
                        .resizable()
                        .scaledToFill()
                } else if isLoading {
                    ProgressView()
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: imageSize.width, height: imageSize.height)
        .subtleBackground()
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .task(id: attachment.resolvedURL) {
            await loadImage()
        }
        .quickLookPreview($previewURL)
    }

    private var imageSize: CGSize {
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

    private func loadImage() async {
        guard let urlString = attachment.resolvedURL else { return }

        isLoading = true
        defer { isLoading = false }

        loadedImage = await AuthenticatedImageLoader.loadImage(urlString: urlString)
    }

    private func openQuickLook() async {
        guard let urlString = attachment.resolvedURL else { return }

        let fileExtension: String
        if let fileName = attachment.fileName, let ext = fileName.split(separator: ".").last, !ext.isEmpty {
            fileExtension = String(ext)
        } else if attachment.isGif == true {
            fileExtension = "gif"
        } else {
            fileExtension = "png"
        }

        guard let localURL = await AuthenticatedImageLoader.downloadToTempFile(
            urlString: urlString,
            fileExtension: fileExtension
        ) else { return }

        previewURL = localURL
    }
}
