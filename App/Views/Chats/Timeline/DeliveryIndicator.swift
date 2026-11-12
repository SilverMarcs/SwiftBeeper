import Foundation

/// The caption under the newest message when the user sent it, as in
/// Messages: each step replaces the last in place.
enum DeliveryIndicator: Equatable {
    /// Not yet with the homeserver or, in a bridged chat, the network.
    case sending
    case sent
    case delivered
    case read

    var label: String {
        switch self {
        case .sending: "Sending…"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .read: "Read"
        }
    }

    /// The caption below the newest row: an optimistic row's while it sends
    /// (a failed one shows its retry instead), or else the newest confirmed
    /// message's.
    static func newest(outgoing: [OutgoingMessage], confirmed: DeliveryIndicator?) -> DeliveryIndicator? {
        guard let last = outgoing.last else { return confirmed }
        return last.state == .sending ? .sending : nil
    }
}
