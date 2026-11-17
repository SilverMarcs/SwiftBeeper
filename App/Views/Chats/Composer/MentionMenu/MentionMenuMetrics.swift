#if os(macOS)
import CoreGraphics

/// The mention menu's geometry, matched to a macOS menu.
enum MentionMenuMetrics {
    /// Between the menu's edge and its items.
    static let inset: CGFloat = 5
    /// Between an item's highlight and its content.
    static let itemPadding: CGFloat = 7
    static let itemCornerRadius: CGFloat = 6
    static let cornerRadius: CGFloat = 11
    static let minimumWidth: CGFloat = 180
    static let maximumWidth: CGFloat = 320
    static let avatarDimension: CGFloat = 18
    static let avatarSpacing: CGFloat = 6
    /// Between the menu and the line it's anchored to, enough to clear the
    /// field's padding above a single line.
    static let lineSpacing: CGFloat = 10

    /// From the menu's leading edge to an item's name, which lines up with
    /// the @ being typed, the avatars hanging to its left.
    static var nameOffset: CGFloat { inset + itemPadding + avatarDimension + avatarSpacing }
}
#endif
