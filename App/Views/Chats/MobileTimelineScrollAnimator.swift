#if os(iOS)
import UIKit

/// Drives only explicit bottom scrolling. Updating the real offset each frame
/// keeps UICollectionView reusing cells throughout the eased transition.
@MainActor
final class MobileTimelineScrollAnimator: NSObject {
    private weak var viewport: MobileTimelineViewport?
    private var displayLink: CADisplayLink?
    private var startOffset = CGPoint.zero
    private var startTime: CFTimeInterval = 0
    private let duration: CFTimeInterval = 0.3

    func scrollToLatest(in viewport: MobileTimelineViewport, animated: Bool) {
        cancel()
        let collection = viewport.collectionView
        let target = viewport.latestContentOffset
        guard animated, !UIAccessibility.isReduceMotionEnabled,
              abs(target.y - collection.contentOffset.y) > 0.5 else {
            collection.setContentOffset(target, animated: false)
            return
        }

        self.viewport = viewport
        startOffset = collection.contentOffset
        startTime = CACurrentMediaTime()
        collection.isFollowingLatest = true
        viewport.chatLayout.keepContentOffsetAtBottomOnBatchUpdates = false
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        viewport?.collectionView.isFollowingLatest = false
        viewport?.chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        viewport = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let viewport, viewport.window != nil,
              !viewport.collectionView.isDragging else {
            cancel()
            return
        }
        guard !viewport.collectionView.hasUncommittedUpdates else { return }

        let progress = min(1, max(0, (link.targetTimestamp - startTime) / duration))
        // Smootherstep starts and ends with zero velocity and acceleration.
        let eased = progress * progress * progress * (progress * (6 * progress - 15) + 10)
        let target = viewport.latestContentOffset
        viewport.collectionView.setContentOffset(CGPoint(
            x: target.x,
            y: startOffset.y + (target.y - startOffset.y) * eased
        ), animated: false)
        if progress == 1 { cancel() }
    }
}
#endif
