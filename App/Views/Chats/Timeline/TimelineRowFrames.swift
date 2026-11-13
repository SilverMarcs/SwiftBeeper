import SwiftUI

/// Where each message row sits, so a tapped quote can move the messages it
/// shows up from rows the reader can see. Rows report their frame in the
/// scroll view, for whether they're on screen, and their bottom edge in the
/// timeline content, which stays put however the timeline scrolls.
///
/// A plain reference type rather than `@Observable`: rows report their frames
/// on every scroll frame, and nothing should re-render because of it.
@MainActor
final class TimelineRowFrames {
    private var visibleFrames: [Message.ID: CGRect] = [:]
    private var contentBottomEdges: [Message.ID: CGFloat] = [:]
    var containerHeight: CGFloat = 0

    func update(_ rowID: Message.ID, visibleFrame: CGRect?) {
        visibleFrames[rowID] = visibleFrame
    }

    func update(_ rowID: Message.ID, contentBottomEdge: CGFloat?) {
        contentBottomEdges[rowID] = contentBottomEdge
    }

    func reset() {
        visibleFrames.removeAll()
        contentBottomEdges.removeAll()
    }

    /// The bottom edge, in the timeline content's space, of each row in
    /// `rowIDs` that is at least partly on screen, keyed by row ID.
    func visibleBottomEdges(of rowIDs: Set<Message.ID>) -> [Message.ID: CGFloat] {
        var edges: [Message.ID: CGFloat] = [:]
        for rowID in rowIDs {
            guard let frame = visibleFrames[rowID], frame.maxY > 0, frame.minY < containerHeight,
                  let edge = contentBottomEdges[rowID] else { continue }
            edges[rowID] = edge
        }
        return edges
    }
}
