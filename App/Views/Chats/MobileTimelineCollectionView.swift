#if os(iOS)
import ChatLayout
import UIKit

/// Native bars can resize the visible area through adjusted insets without
/// changing the collection's bounds, including the searchable composer.
final class MobileTimelineCollectionView: UICollectionView {
    var isFollowingLatest = false
    private var previousAdjustedContentInset: UIEdgeInsets = .zero

    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()

        let previousInset = previousAdjustedContentInset
        let currentInset = adjustedContentInset
        previousAdjustedContentInset = currentInset

        let layout = collectionViewLayout as? CollectionViewChatLayout
        let bottomInsetChange = currentInset.bottom - previousInset.bottom
        let snapshot = bottomInsetChange != 0 && window != nil && alpha > 0
            && !isFollowingLatest && !isTracking && !isDecelerating
            ? layout?.getContentOffsetSnapshot(from: .bottom) : nil

        if let layout, let snapshot {
            // The callback already exposes the new inset. Recover the anchor's
            // distance from the previous visible bottom before restoring it.
            layout.restoreContentOffset(with: ChatLayoutPositionSnapshot(
                indexPath: snapshot.indexPath,
                edge: .bottom,
                offset: snapshot.offset + bottomInsetChange
            ))
        }
    }
}
#endif
