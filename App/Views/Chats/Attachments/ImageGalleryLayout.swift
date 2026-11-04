import CoreGraphics

/// How a photo gallery tiles its images: equal squares spanning the media
/// bubble's width. Three photos share one row; otherwise two go across, and
/// at most four show, the last counting the rest. The fullscreen viewer still
/// pages through every photo.
struct ImageGalleryLayout {
    static let spacing: CGFloat = 2
    private static let maxVisibleCount = 4

    let imageCount: Int

    var columns: Int { imageCount == 3 ? 3 : 2 }
    var visibleCount: Int { min(imageCount, Self.maxVisibleCount) }
    /// Photos left out of the grid, shown as "+N" on its last tile.
    var hiddenCount: Int { imageCount - visibleCount }

    /// The image indices in each grid row.
    var rows: [[Int]] {
        stride(from: 0, to: visibleCount, by: columns).map { start in
            Array(start..<min(start + columns, visibleCount))
        }
    }

    /// Every tile's side. Fixed up front so the row keeps its height while
    /// the images load, and the timeline doesn't jump.
    var tileSide: CGFloat {
        let gaps = Self.spacing * CGFloat(columns - 1)
        return (MediaBubbleSize.maxWidth - gaps) / CGFloat(columns)
    }

    /// The number shown over `index`, or zero when it shows none.
    func hiddenCount(onTile index: Int) -> Int {
        index == visibleCount - 1 ? hiddenCount : 0
    }
}
