import Foundation

/// The chat list's row order, for animating reorders. Orders where one only
/// extends the other count as equal, so a page appended below, or trimmed off
/// the end, doesn't animate.
struct ChatListOrder: Equatable {
    let ids: [String]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ids.starts(with: rhs.ids) || rhs.ids.starts(with: lhs.ids)
    }
}
