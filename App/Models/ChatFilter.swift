import Foundation

enum ChatFilter: Hashable, Identifiable {
    case inbox(InboxFilter)
    /// One network login's chats, in its primary inbox.
    case network(NetworkFilter)

    var id: String {
        switch self {
        case .inbox(let inbox): "inbox_\(inbox.rawValue)"
        case .network(let network): "network_\(network.accountID)"
        }
    }

    var accountIDs: [String] {
        guard case .network(let network) = self else { return [] }
        return [network.accountID]
    }
}
