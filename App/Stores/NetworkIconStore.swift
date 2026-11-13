import CoreGraphics
import Observation
import SwiftUI

/// The network logos and workspace icons the filter menu shows, drawn ahead
/// of time: a menu takes its images as finished bitmaps, so it can't load
/// them itself the way a view can.
@MainActor
@Observable
final class NetworkIconStore {
    /// Icons by their image URL.
    private(set) var icons: [String: Image] = [:]
    @ObservationIgnored private var loadingURLs: Set<String> = []

    /// Loads the icon of every filter that has an image and isn't loaded yet.
    func load(_ filters: [NetworkFilter], pointSize: CGFloat, displayScale: CGFloat) async {
        let pixelSize = Int((pointSize * displayScale).rounded())
        for filter in filters {
            guard let imageURL = filter.imageURL, icons[imageURL] == nil,
                  loadingURLs.insert(imageURL).inserted else { continue }
            defer { loadingURLs.remove(imageURL) }
            guard let file = await MatrixMedia.localFile(for: imageURL),
                  let icon = await Self.renderIcon(file, pixelSize: pixelSize, rounded: filter.isWorkspaceImage)
            else { continue }
            icons[imageURL] = Image(decorative: icon, scale: displayScale)
        }
    }

    @concurrent
    private nonisolated static func renderIcon(_ file: URL, pixelSize: Int, rounded: Bool) async -> CGImage? {
        MenuIconRenderer.icon(contentsOf: file, pixelSize: pixelSize, rounded: rounded)
    }
}
