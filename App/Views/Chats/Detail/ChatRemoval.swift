import Foundation

/// A way of removing a chat from chat info, and how it's confirmed.
enum ChatRemoval {
    case leave
    case delete

    var confirmationTitle: String {
        switch self {
        case .leave: String(localized: "Leave this group?")
        case .delete: String(localized: "Delete this chat?")
        }
    }

    var actionTitle: String {
        switch self {
        case .leave: String(localized: "Leave Group")
        case .delete: String(localized: "Delete Chat")
        }
    }

    func confirmationMessage(network: String?, canDeleteChat: Bool) -> String {
        let network = network ?? String(localized: "the network")
        switch self {
        case .leave:
            return String(localized: "You'll stop receiving its messages, and its members will see that you left.")
        case .delete where canDeleteChat:
            return String(localized: "The chat and its messages are deleted from \(network) and Relay.")
        case .delete:
            return String(localized: "The chat is removed from Relay but stays on \(network). It may come back if someone sends a new message.")
        }
    }
}
