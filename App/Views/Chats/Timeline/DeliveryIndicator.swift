import Foundation

/// The caption under the newest message when the user sent it, as in
/// Messages: each step replaces the last in place.
enum DeliveryIndicator: Equatable {
    /// Not yet with the homeserver or, in a bridged chat, the network.
    case sending
    case sent
    case delivered
    case seen
    /// In a group, who has seen it, ordered by first name. Shown as their
    /// avatars; `label` names them for accessibility.
    case seenBy([DeliveryReader])
    /// In a group, everyone else has seen it.
    case seenByAll

    /// Names a group caption lists before counting the rest.
    private static let listedNameLimit = 3

    var label: String {
        switch self {
        case .sending: "Sending…"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .seen: "Seen"
        case .seenBy(let readers): "Seen by \(Self.nameList(readers.map { Self.firstName(of: $0.name) }))"
        case .seenByAll: "Seen by all"
        }
    }

    /// The caption below the newest row: an optimistic row's while it sends
    /// (a failed one shows its retry instead), or else the newest confirmed
    /// message's.
    static func newest(outgoing: [OutgoingMessage], confirmed: DeliveryIndicator?) -> DeliveryIndicator? {
        guard let last = outgoing.last else { return confirmed }
        return last.state == .sending ? .sending : nil
    }

    /// The first word of a name, unless that isn't a name at all, such as
    /// the country code of a phone number.
    static func firstName(of name: String) -> String {
        guard let first = name.split(whereSeparator: \.isWhitespace).first,
              first.contains(where: \.isLetter) else { return name }
        return String(first)
    }

    /// "Daniel, Julian, and Sahab", or "Daniel, Julian, Sahab, and 2 others".
    private static func nameList(_ names: [String]) -> String {
        guard names.count > listedNameLimit else { return names.formatted(.list(type: .and)) }
        let others = names.count - listedNameLimit
        let listed = Array(names.prefix(listedNameLimit)) + [others == 1 ? "1 other" : "\(others) others"]
        return listed.formatted(.list(type: .and))
    }
}
