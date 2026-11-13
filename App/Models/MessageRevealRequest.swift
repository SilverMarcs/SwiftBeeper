import Foundation

/// A request to scroll the open timeline to a message. Each request is new,
/// so revealing the same message twice scrolls both times.
struct MessageRevealRequest: Equatable {
    let messageID: Message.ID
    let id = UUID()
}
