import CoreGraphics

/// Frame rules shared by image and video bubbles, sent or still sending.
enum MediaBubbleSize {
    static let maxWidth: CGFloat = Device.isMacOrPad ? 400 : 275
    static let maxHeight: CGFloat = 500
    /// Decode size in pixels — large enough that SMV's fullscreen viewer
    /// (which reuses the same cached decode) stays sharp.
    static let decodePixelSize = 650

    /// Scales the media down (never up) to fit the bubble bounds, keeping its
    /// aspect ratio. Unknown sizes get a square bubble.
    static func fitting(_ size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: maxWidth, height: maxWidth)
        }
        let scale = min(maxWidth / size.width, maxHeight / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    static func fitting(_ size: AttachmentSize?) -> CGSize {
        fitting(CGSize(width: size?.width ?? 0, height: size?.height ?? 0))
    }
}
