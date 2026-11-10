import Foundation

/// One list entry: its bullet or number, and what follows it.
struct MessageListItem {
    /// "•", "◦" or "▪" by depth, or the item's number such as "2.".
    let marker: String
    let blocks: [MessageBlock]
}
