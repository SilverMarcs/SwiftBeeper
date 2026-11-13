#if os(iOS)
import SwiftUI

/// Lays out the composer bar, so moving between its states animates every
/// part from one place to the other.
///
/// It's one row, as the system bottom bar it replaced: the attachment
/// button's circle, then the field's
/// glass with the editor and, in a slot at its trailing end, dictation or
/// Send. While the editor has focus the bar reaches nearer the edges, as a
/// focused search field does, and the field grows upwards with the draft;
/// the buttons stay on its bottom line.
struct ComposerBarLayout: Layout {
    var isFocused: Bool
    /// The editor's height, at least `rowHeight`.
    var editorHeight: CGFloat

    /// The system bottom bar's metrics, which the composer at rest matches.
    static let rowHeight: CGFloat = 48
    static let restingMargin: CGFloat = 28
    static let spacing: CGFloat = 12
    /// Focused, the bar nearly reaches the edges, as a focused search field
    /// does.
    static let focusedMargin: CGFloat = 8
    static let cornerRadius: CGFloat = rowHeight / 2
    /// The slot at the field's end that dictation and Send share.
    static let trailingSlotWidth: CGFloat = 44
    /// Between the field's end and the trailing slot.
    private static let trailingSlotInset: CGFloat = 4

    /// The editor's width in a bar `width` wide.
    static func editorWidth(in width: CGFloat, isFocused: Bool) -> CGFloat {
        let margin = isFocused ? focusedMargin : restingMargin
        let leading = margin + rowHeight + spacing
        return max(width - margin - leading - trailingSlotWidth - trailingSlotInset, 0)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 402, height: max(editorHeight, Self.rowHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(in: bounds, subviews: subviews)
        for subview in subviews {
            let frame = frames[subview.composerBarPart] ?? .zero
            subview.place(at: frame.origin, anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(in bounds: CGRect, subviews: Subviews) -> [ComposerBarPart: CGRect] {
        let row = Self.rowHeight
        let margin = isFocused ? Self.focusedMargin : Self.restingMargin
        // The buttons sit on the bottom line as the field grows.
        let rowY = bounds.maxY - row
        var frames: [ComposerBarPart: CGRect] = [:]
        var leading = bounds.minX + margin
        let trailing = bounds.maxX - margin

        frames[.attach] = CGRect(x: leading, y: rowY, width: row, height: row)
        if subviews.contains(where: { $0.composerBarPart == .attach }) { leading += row + Self.spacing }

        frames[.panel] = CGRect(x: leading, y: bounds.minY, width: max(trailing - leading, 0), height: bounds.height)

        let slot = CGRect(x: trailing - Self.trailingSlotInset - Self.trailingSlotWidth, y: rowY,
                          width: Self.trailingSlotWidth, height: row)
        for part in [ComposerBarPart.dictation, .send] {
            guard let subview = subviews.first(where: { $0.composerBarPart == part }) else { continue }
            let size = subview.sizeThatFits(.unspecified)
            frames[part] = CGRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2,
                                  width: size.width, height: size.height)
        }
        frames[.editor] = CGRect(x: leading, y: bounds.minY, width: max(slot.minX - leading, 0), height: bounds.height)
        return frames
    }
}
#endif
