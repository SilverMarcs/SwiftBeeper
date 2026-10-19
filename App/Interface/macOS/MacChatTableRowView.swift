#if os(macOS)
import AppKit

@MainActor
final class MacChatTableRowView: NSTableRowView {
    override var isNextRowSelected: Bool {
        didSet { needsDisplay = true }
    }

    override func drawSeparator(in dirtyRect: NSRect) {
        guard !isSelected, !isNextRowSelected,
              let cell = view(atColumn: 0) as? NSTableCellView,
              let title = cell.textField else { return }
        // Align to the primary label instead of letting trailing dates or badges
        // change AppKit's inferred separator inset from one row to another.
        let leading = convert(title.bounds, from: title).minX
        let trailing = convert(cell.bounds, from: cell).maxX - 5
        let pixel = 1 / (window?.backingScaleFactor ?? 2)
        NSColor.separatorColor.setFill()
        NSRect(x: leading, y: bounds.maxY - pixel,
               width: max(0, trailing - leading), height: pixel).fill()
    }
}
#endif
