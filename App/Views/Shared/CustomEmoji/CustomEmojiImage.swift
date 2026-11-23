import SwiftUI

/// A bridged custom emoji's image in a square, animated when it's a GIF
/// unless Reduce Motion is on. Empty while it loads or if it can't.
struct CustomEmojiImage: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The emoji's mxc:// source.
    let source: String
    let dimension: CGFloat

    @State private var loadedFrames: CustomEmojiFrames?

    var body: some View {
        let pixelSize = Self.pixelSize(for: dimension, scale: displayScale)
        let frames = loadedFrames ?? CustomEmojiFrames.cached(source, pixelSize: pixelSize)
        Group {
            if let frames {
                if frames.isAnimated, !reduceMotion {
                    AnimatedEmojiView(frames: frames)
                } else if let image = frames.images.first {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Color.clear
            }
        }
        .frame(width: dimension, height: dimension)
        .task(id: "\(pixelSize) \(source)") {
            loadedFrames = await CustomEmojiFrames.load(source, pixelSize: pixelSize)
        }
        .accessibilityHidden(true)
    }

    /// The emoji's decoded size, also how the reaction details picker finds
    /// the frames the pills already decoded.
    static func pixelSize(for dimension: CGFloat, scale: CGFloat) -> Int {
        Int((dimension * scale).rounded(.up))
    }
}
