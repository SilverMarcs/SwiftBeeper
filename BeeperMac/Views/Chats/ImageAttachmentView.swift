import SwiftUI

struct ImageAttachmentView: View {
    @Environment(SessionStore.self) private var sessionStore

    let attachment: Attachment

    @State private var loadedImage: Image?
    @State private var isLoading = false

    var body: some View {
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
        guard let urlString = attachment.resolvedURL else { return }

        isLoading = true
        defer { isLoading = false }

        loadedImage = await AuthenticatedImageLoader.loadImage(urlString: urlString, accessToken: sessionStore.accessToken)
    }
}
