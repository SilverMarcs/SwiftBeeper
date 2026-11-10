#if os(macOS)
import CoreGraphics

/// Sizes the main window and the thread inspector share, so the window's
/// minimum always leaves the inspector room.
enum MainWindowLayout {
    static let minimumWidth: CGFloat = 900
    static let minimumHeight: CGFloat = 600
    static let threadInspectorMinimumWidth: CGFloat = 280
    static let threadInspectorIdealWidth: CGFloat = 320
    /// The most the inspector can be dragged to. The window's minimum sets
    /// this much aside, so any width in the range fits.
    static let threadInspectorMaximumWidth: CGFloat = 420
}
#endif
