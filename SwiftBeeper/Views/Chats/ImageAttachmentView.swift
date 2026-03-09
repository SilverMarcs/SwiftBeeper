import SwiftUI

struct ImageAttachmentView: View {
    @Environment(SessionStore.self) private var sessionStore

    let attachment: Attachment

    @State private var loadedImage: Image?
    @State private var isLoading = false
    @State private var showFullImage = false

    private let thumbnailWidth: CGFloat = 330
    private let thumbnailHeight: CGFloat = 330

    var body: some View {
        Group {
            if let loadedImage {
                Button {
                    showFullImage = true
                } label: {
                    loadedImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: thumbnailWidth, height: thumbnailHeight)
                        .clipped()
                        .clipShape(.rect(cornerRadius: 12))
                        .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else if isLoading {
                ProgressView()
                    .frame(width: thumbnailWidth, height: thumbnailHeight)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                    .frame(width: thumbnailWidth, height: thumbnailHeight)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .task(id: "\(attachment.resolvedURL ?? "none")|\(sessionStore.accessToken)") {
            await loadImage()
        }
        .sheet(isPresented: $showFullImage) {
            if let loadedImage {
                FullImageSheet(image: loadedImage)
            }
        }
    }

    private func loadImage() async {
        guard let urlString = attachment.resolvedURL else { return }

        isLoading = true
        defer { isLoading = false }

        loadedImage = await AuthenticatedImageLoader.loadImage(urlString: urlString, accessToken: sessionStore.accessToken)
    }
}

private struct FullImageSheet: View {
    let image: Image
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding()
            }
    }
}
