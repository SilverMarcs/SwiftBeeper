#if os(iOS)
import AVFoundation
import UIKit

/// A view backed by an `AVPlayerLayer`, so the layer follows its bounds.
final class PlayerLayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    // The backing layer is always an AVPlayerLayer, per `layerClass`.
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspect
    }
}
#endif
