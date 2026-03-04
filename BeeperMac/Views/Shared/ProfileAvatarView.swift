import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ProfileAvatarView: View {
    @AppStorage("beeperAccessToken") private var accessToken = ""

    let name: String
    let imageURLString: String?
    let dimension: CGFloat
    @State private var loadedImage: Image?

    var body: some View {
        Group {
            if let loadedImage {
                loadedImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: dimension, height: dimension)
                    .clipShape(.circle)
            } else {
                initialsAvatar
            }
        }
        .task(id: imageRequestKey) {
            await loadImage()
        }
    }

    private var imageRequestKey: String {
        "\(imageURLString ?? "none")|\(accessToken)"
    }

    private func loadImage() async {
        guard let request = imageRequest else {
            loadedImage = nil
            return
        }

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
        guard let imageURLString, imageURLString.isEmpty == false else {
            return nil
        }

        guard let sourceURL = URL(string: imageURLString) else {
            return nil
        }

        if sourceURL.scheme == "mxc" || sourceURL.scheme == "localmxc" || sourceURL.scheme == "file" {
            guard var components = URLComponents(string: "http://localhost:23373/v1/assets/serve") else {
                return nil
            }
            components.queryItems = [
                URLQueryItem(name: "url", value: imageURLString)
            ]
            guard let proxyURL = components.url else {
                return nil
            }

            var request = URLRequest(url: proxyURL)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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

    private var initialsAvatar: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(initials)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.primary)
            }
            .frame(width: dimension, height: dimension)
    }

    private var initials: String {
        let words = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")

        let pickedCharacters = words.prefix(2).compactMap { word in
            word.first.map(String.init)
        }

        if pickedCharacters.isEmpty {
            return "?"
        }

        return pickedCharacters.joined()
    }
}

#Preview {
    ProfileAvatarView(name: "Alice Wonder", imageURLString: nil, dimension: 36)
}
