import SwiftUI

/// A custom emoji's animation, played by Core Animation.
#if os(macOS)
struct AnimatedEmojiView: NSViewRepresentable {
    let frames: CustomEmojiFrames

    func makeNSView(context: Context) -> AnimatedEmojiLayerView {
        AnimatedEmojiLayerView(frame: .zero)
    }

    func updateNSView(_ view: AnimatedEmojiLayerView, context: Context) {
        view.frames = frames
    }
}
#else
struct AnimatedEmojiView: UIViewRepresentable {
    let frames: CustomEmojiFrames

    func makeUIView(context: Context) -> AnimatedEmojiLayerView {
        AnimatedEmojiLayerView(frame: .zero)
    }

    func updateUIView(_ view: AnimatedEmojiLayerView, context: Context) {
        view.frames = frames
    }
}
#endif
