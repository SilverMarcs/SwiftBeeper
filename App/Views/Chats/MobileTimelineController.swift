#if os(iOS)
import ChatLayout
import UIKit

/// Explicit navigation uses the same upright coordinates as the layout. The
/// initial bottom anchor is established during layout, before showing the list.
@MainActor
final class MobileTimelineController {
    weak var viewport: MobileTimelineViewport? {
        didSet {
            guard oldValue !== viewport else { return }
            scrollAnimator.cancel()
            hasPositionedInitialContent = false
            isPositioningInitialContent = false
            isApplyingSnapshot = false
        }
    }
    var indexPathForMessage: ((String) -> IndexPath?)?
    var lastIndexPath: (() -> IndexPath?)?
    var isApplyingSnapshot = false
    private(set) var hasPositionedInitialContent = false
    private var isPositioningInitialContent = false
    private var pendingRequest: (messageID: String?, animated: Bool)?
    private let scrollAnimator = MobileTimelineScrollAnimator()

    /// One owner from the queued send request through the final animation frame.
    var isFollowingLatest: Bool {
        if let request = pendingRequest, request.messageID == nil { return true }
        return viewport?.collectionView.isFollowingLatest == true
    }

    func prepareForInitialContent() {
        if !hasPositionedInitialContent { viewport?.collectionView.alpha = 0 }
    }

    func scrollToLatest(animated: Bool) {
        pendingRequest = (nil, animated)
        performPendingRequest()
    }

    func scrollToMessage(_ id: String, animated: Bool = true) {
        pendingRequest = (id, animated)
        performPendingRequest()
    }

    func cancelAutomaticScroll() {
        pendingRequest = nil
        scrollAnimator.cancel()
    }

    func performPendingRequest() {
        guard !isApplyingSnapshot, !isPositioningInitialContent, let viewport,
              viewport.window != nil, viewport.collectionView.bounds.height > 0,
              !viewport.collectionView.hasUncommittedUpdates else { return }
        let collectionView = viewport.collectionView
        collectionView.layoutIfNeeded()

        if !hasPositionedInitialContent {
            guard let last = lastIndexPath?() else {
                collectionView.alpha = 1
                return
            }
            isPositioningInitialContent = true
            UIView.performWithoutAnimation {
                viewport.chatLayout.restoreContentOffset(with: ChatLayoutPositionSnapshot(indexPath: last, edge: .bottom))
                collectionView.alpha = 1
            }
            hasPositionedInitialContent = true
            isPositioningInitialContent = false
        }

        guard let request = pendingRequest else { return }
        pendingRequest = nil
        if let id = request.messageID, let indexPath = indexPathForMessage?(id) {
            scrollAnimator.cancel()
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: request.animated)
        } else if request.messageID == nil {
            scrollAnimator.scrollToLatest(in: viewport, animated: request.animated)
        }
    }
}
#endif
