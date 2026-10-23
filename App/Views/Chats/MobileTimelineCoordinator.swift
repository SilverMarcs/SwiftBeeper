#if os(iOS)
import ChatLayout
import SwiftUI
import UIKit

@MainActor
final class MobileTimelineCoordinator: NSObject, UICollectionViewDelegate, ChatLayoutDelegate {
    var onLoadOlder: (() -> Void)?
    var onTapLinkedMessage: ((String) -> Void)?
    private let controller: MobileTimelineController
    private let chatStore: ChatStore
    private let inputManager: InputManager
    private weak var viewport: MobileTimelineViewport?
    private var dataSource: ChatLayoutDiffableDataSource<Int, String>?
    private var appliedRows: [MobileTimelineRow] = []
    private var rowsByID: [String: MobileTimelineRow] = [:]
    private var pendingRows: [MobileTimelineRow]?
    private var isApplying = false
    private let sizingCell = MobileTimelineCell(frame: .zero)
    private var preparedSizes: [String: CGSize] = [:]
    private var preparedWidth: CGFloat = 0

    init(controller: MobileTimelineController, chatStore: ChatStore, inputManager: InputManager) {
        self.controller = controller
        self.chatStore = chatStore
        self.inputManager = inputManager
    }

    func attach(to viewport: MobileTimelineViewport) {
        self.viewport = viewport
        controller.viewport = viewport
        viewport.collectionView.delegate = self
        viewport.chatLayout.delegate = self
        // Inherit the real viewport's typography and traits while measuring,
        // without drawing another row or exposing it to accessibility/touches.
        sizingCell.alpha = 0
        sizingCell.isUserInteractionEnabled = false
        sizingCell.accessibilityElementsHidden = true
        viewport.addSubview(sizingCell)
        dataSource = ChatLayoutDiffableDataSource<Int, String>(collectionView: viewport.collectionView) { [weak self] collection, indexPath, id in
            guard let self, let row = rowsByID[id] else { return nil }
            let cell = collection.dequeueReusableCell(withReuseIdentifier: "message", for: indexPath)
            cell.backgroundColor = .clear
            cell.contentConfiguration = configuration(for: row)
            return cell
        }
        controller.indexPathForMessage = { [weak self] id in self?.dataSource?.indexPath(for: id) }
        controller.lastIndexPath = { [weak self] in
            guard let self, !appliedRows.isEmpty else { return nil }
            return IndexPath(item: appliedRows.count - 1, section: 0)
        }
    }

    func update(_ rows: [MobileTimelineRow]) {
        guard !isApplying else {
            pendingRows = rows
            return
        }
        guard rows != appliedRows, let dataSource else { return }
        let previous = Dictionary(uniqueKeysWithValues: appliedRows.map { ($0.id, $0) })
        let tailChanged = appliedRows.last?.id != rows.last?.id
        let replacesOutgoingTail: Bool
        if case let .outgoing(outgoing, _, _) = appliedRows.last?.content,
           case let .message(message, _, _, _, _) = rows.last?.content {
            replacesOutgoingTail = outgoing.matchesConfirmedMessage(message)
        } else {
            replacesOutgoingTail = false
        }
        let followsTail = controller.hasPositionedInitialContent && tailChanged
            && rows.count >= appliedRows.count && !replacesOutgoingTail
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(rows.map(\.id))
        snapshot.reconfigureItems(rows.filter { previous[$0.id] != nil && previous[$0.id] != $0 }.map(\.id))
        isApplying = true
        controller.isApplyingSnapshot = true
        controller.prepareForInitialContent()
        if followsTail {
            // Store the intent while applying; consume it once the final queued
            // snapshot and its complete row heights are committed.
            controller.scrollToLatest(animated: true)
        }
        preparedSizes.removeAll(keepingCapacity: true)
        if followsTail || replacesOutgoingTail, let viewport {
            preparedWidth = viewport.chatLayout.layoutFrame.width
            if preparedWidth > 0 {
                // A prototype at y=0 inherits the status/navigation-bar inset.
                // Measure inside the safe area, as a real collection cell does.
                sizingCell.frame.origin = viewport.safeAreaLayoutGuide.layoutFrame.origin
                for row in rows where previous[row.id] != row {
                    sizingCell.contentConfiguration = configuration(for: row, animatesSend: false)
                    preparedSizes[row.id] = sizingCell.fittedSize(width: preparedWidth)
                }
                sizingCell.contentConfiguration = nil
            }
        }

        // Appending for an explicit bottom scroll must preserve the starting
        // offset. Automatic batch compensation would jump to the destination
        // before our animation even starts. Pagination keeps native anchoring.
        viewport?.chatLayout.keepContentOffsetAtBottomOnBatchUpdates = !controller.isFollowingLatest

        // Commit row models at the layout engine's transaction boundary, so
        // self-sizing and identifier lookups see the same snapshot.
        dataSource.apply(snapshot, animatingDifferences: false, commitAlongsideUpdates: { [self] in
            appliedRows = rows
            rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        }, completion: { [weak self] in
            guard let self, controller.viewport === viewport else { return }
            isApplying = false
            if let pending = pendingRows, pending != appliedRows {
                pendingRows = nil
                update(pending)
            } else {
                pendingRows = nil
                controller.isApplyingSnapshot = false
                controller.performPendingRequest()
                viewport?.chatLayout.keepContentOffsetAtBottomOnBatchUpdates = !controller.isFollowingLatest
                loadOlderIfNeeded()
            }
        })
    }

    private func configuration(for row: MobileTimelineRow, animatesSend: Bool = true) -> some UIContentConfiguration {
        UIHostingConfiguration {
            MobileTimelineRowView(row: row) { [weak self] id in
                self?.onTapLinkedMessage?(id)
            }
            .environment(self.chatStore)
            .environment(self.inputManager)
            .environment(\.messageSendAnimationsEnabled, animatesSend)
        }
        .margins(.all, 0)
        .minSize(width: 0, height: 0)
    }

    func sizeForItem(_ chatLayout: CollectionViewChatLayout, at indexPath: IndexPath) -> ItemSize {
        guard preparedWidth == chatLayout.layoutFrame.width,
              appliedRows.indices.contains(indexPath.item),
              let size = preparedSizes[appliedRows[indexPath.item].id] else { return .auto }
        return .estimated(size)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        loadOlderIfNeeded()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        controller.cancelAutomaticScroll()
    }

    private func loadOlderIfNeeded() {
        guard !isApplying, !appliedRows.isEmpty, controller.hasPositionedInitialContent,
              let collection = viewport?.collectionView, !collection.isFollowingLatest, collection.bounds.height > 0,
              collection.contentOffset.y < -collection.adjustedContentInset.top + 80 else { return }
        onLoadOlder?()
    }
}
#endif
