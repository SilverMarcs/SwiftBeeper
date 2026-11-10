import SwiftUI

/// Keeps the reader's place when rows change above them, chiefly a page of
/// older messages. SwiftUI keeps the content offset when rows are inserted
/// above while the reader is scrolling, which would otherwise show the top of
/// the new page, 40 messages back. Rows report where they sit, and after a
/// change the row that was at the top edge is scrolled back to the same spot.
///
/// A plain reference type rather than `@Observable`: rows report their frames
/// on every scroll frame, and nothing should re-render because of it.
final class TimelineScrollAnchor {
    /// Row frames in the scroll view's coordinate space, for laid-out rows only.
    private var frames: [String: CGRect] = [:]
    private var containerHeight: CGFloat = 0

    func update(_ rowID: String, frame: CGRect?) {
        frames[rowID] = frame
    }

    func update(_ geometry: ScrollGeometry) {
        containerHeight = geometry.containerSize.height
    }

    func reset() {
        frames.removeAll()
    }

    /// The row at the top edge, and the unit point that puts it back where it
    /// is now. `scrollTo` lines up the same unit point of the row and of the
    /// viewport, so the point is the row's offset over the room left around it.
    func current() -> (rowID: String, anchor: UnitPoint)? {
        let visible = frames.filter { $0.value.maxY > 0 }
        guard let top = visible.min(by: { $0.value.minY < $1.value.minY }) else { return nil }
        let room = containerHeight - top.value.height
        let y = abs(room) > 1 ? top.value.minY / room : 0
        return (top.key, UnitPoint(x: 0.5, y: y))
    }
}
