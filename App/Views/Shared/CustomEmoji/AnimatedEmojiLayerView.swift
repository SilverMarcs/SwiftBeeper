import QuartzCore

#if os(macOS)
import AppKit
typealias AnimatedEmojiBaseView = NSView
#else
import UIKit
typealias AnimatedEmojiBaseView = UIView
#endif

/// Plays a custom emoji's frames as a Core Animation keyframe animation, so
/// the render server animates it without redrawing any SwiftUI view. Passes
/// every touch and click through to the pill around it.
final class AnimatedEmojiLayerView: AnimatedEmojiBaseView {
    var frames: CustomEmojiFrames? {
        didSet {
            guard frames !== oldValue else { return }
            restartAnimation()
        }
    }

    private let imageLayer = CALayer()
    private static let animationKey = "frames"

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(macOS)
        wantsLayer = true
        layer?.addSublayer(imageLayer)
        #else
        isUserInteractionEnabled = false
        layer.addSublayer(imageLayer)
        #endif
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if os(macOS)
    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { restartAnimation() }
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        imageLayer.frame = bounds
    }

    // UIKit drops a layer's animations when its view leaves the window, as
    // when a cell is reused or the app goes to the background.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { restartAnimation() }
    }
    #endif

    private func restartAnimation() {
        imageLayer.removeAnimation(forKey: Self.animationKey)
        imageLayer.contents = frames?.images.first
        guard let frames, frames.isAnimated else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames.images
        animation.keyTimes = frames.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .discrete
        animation.duration = frames.duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        imageLayer.add(animation, forKey: Self.animationKey)
    }
}
