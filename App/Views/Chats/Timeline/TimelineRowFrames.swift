import SwiftUI

/// Where each message row and its sender's name and avatar sit, so a tapped
/// quote can move what it shows from where the reader can see it. Rows
/// report their frame in the scroll view, for whether they're on screen, and
/// bottom edges in the timeline content, which stay put however the
/// timeline scrolls.
///
/// A plain reference type rather than `@Observable`: rows report their frames
/// on every scroll frame, and nothing should re-render because of it.
@MainActor
final class TimelineRowFrames {
    private var visibleFrames: [Message.ID: CGRect] = [:]
    private var contentBottomEdges: [Message.ID: CGFloat] = [:]
    private var senderNameBottomEdges: [Message.ID: CGFloat] = [:]
    private var senderAvatarBottomEdges: [Message.ID: CGFloat] = [:]
    var containerHeight: CGFloat = 0

    func update(_ rowID: Message.ID, visibleFrame: CGRect?) {
        visibleFrames[rowID] = visibleFrame
    }

    func update(_ rowID: Message.ID, contentBottomEdge: CGFloat?) {
        contentBottomEdges[rowID] = contentBottomEdge
    }

    func update(_ rowID: Message.ID, senderNameBottomEdge: CGFloat?) {
        senderNameBottomEdges[rowID] = senderNameBottomEdge
    }

    func update(_ rowID: Message.ID, senderAvatarBottomEdge: CGFloat?) {
        senderAvatarBottomEdges[rowID] = senderAvatarBottomEdge
    }

    func reset() {
        visibleFrames.removeAll()
        contentBottomEdges.removeAll()
        senderNameBottomEdges.removeAll()
        senderAvatarBottomEdges.removeAll()
    }

    /// The bottom edge of each row in `rowIDs` that is at least partly on
    /// screen, keyed by row ID.
    func visibleBottomEdges(of rowIDs: Set<Message.ID>) -> [Message.ID: CGFloat] {
        var edges: [Message.ID: CGFloat] = [:]
        for rowID in rowIDs where isVisible(rowID) {
            edges[rowID] = contentBottomEdges[rowID]
        }
        return edges
    }

    /// The bottom edge of the row's sender's name, while the row is on screen.
    func senderNameBottom(of rowID: Message.ID) -> CGFloat? {
        isVisible(rowID) ? senderNameBottomEdges[rowID] : nil
    }

    /// The bottom edge of the row's avatar, while the row is on screen.
    func senderAvatarBottom(of rowID: Message.ID) -> CGFloat? {
        isVisible(rowID) ? senderAvatarBottomEdges[rowID] : nil
    }

    private func isVisible(_ rowID: Message.ID) -> Bool {
        guard let frame = visibleFrames[rowID] else { return false }
        return frame.maxY > 0 && frame.minY < containerHeight
    }
}

extension EnvironmentValues {
    /// Set on the timeline's rows, which report where their sender's name
    /// and avatar sit; nil elsewhere, as in a quote's chain.
    @Entry var timelineRowFrames: TimelineRowFrames?
}
