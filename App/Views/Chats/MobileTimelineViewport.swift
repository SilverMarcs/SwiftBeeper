#if os(iOS)
import ChatLayout
import UIKit

/// SwiftUI owns the frame and UIKit owns bar insets. Preserve the visible bottom
/// across either kind of geometry change, using ChatLayout's item anchors.
final class MobileTimelineViewport: UIView {
    let chatLayout = CollectionViewChatLayout()
    let collectionView: MobileTimelineCollectionView

    override init(frame: CGRect) {
        chatLayout.keepContentAtBottomOfVisibleArea = true
        chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        chatLayout.supportSelfSizingInvalidation = true
        chatLayout.settings.additionalInsets.bottom = 24
        collectionView = MobileTimelineCollectionView(frame: .zero, collectionViewLayout: chatLayout)
        super.init(frame: frame)
        backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.automaticallyAdjustsScrollIndicatorInsets = true
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.scrollsToTop = false
        collectionView.selfSizingInvalidation = .enabled
        collectionView.register(MobileTimelineCell.self, forCellWithReuseIdentifier: "message")
        collectionView.alpha = 0
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        // Capture the visible bottom row before Auto Layout resizes the list.
        // Restoring it in this same pass follows the keyboard's animation;
        // batch-update anchoring alone doesn't cover viewport size changes.
        let isResizing = collectionView.bounds.size != bounds.size
        let snapshot = isResizing && collectionView.bounds.height > 0
            && !collectionView.isFollowingLatest && !collectionView.isTracking && !collectionView.isDecelerating
            ? chatLayout.getContentOffsetSnapshot(from: .bottom) : nil

        super.layoutSubviews()

        if let snapshot {
            chatLayout.restoreContentOffset(with: snapshot)
        }
    }

    var latestContentOffset: CGPoint {
        CGPoint(
            x: collectionView.contentOffset.x,
            y: max(
                -collectionView.adjustedContentInset.top,
                chatLayout.collectionViewContentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
            )
        )
    }
}
#endif
