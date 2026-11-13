import Foundation

/// One login to filter the chat list by, as the filter menu lists it. Each
/// login is its own filter, so two Slack workspaces list separately.
struct NetworkFilter: Hashable {
    let accountID: String
    let bridgeID: String
    let title: String
    /// Tells apart logins on one network: the network under a workspace's
    /// name, or the login's name under the network's.
    let subtitle: String?
    /// The workspace's icon, or else the network's logo.
    let imageURL: String?
    /// Workspace icons are square photos, drawn rounded; network logos
    /// already have their shape.
    let isWorkspaceImage: Bool

    /// - Parameter sharesNetwork: Whether another login is on the same
    ///   network, so the filter needs the login's name to tell them apart.
    init(account: Account, sharesNetwork: Bool) {
        accountID = account.accountID
        bridgeID = account.bridgeID
        if let workspace = account.workspace, !workspace.name.isBlank {
            title = workspace.name
            subtitle = account.network
            let workspaceImage = workspace.imgURL.flatMap { $0.isBlank ? nil : $0 }
            imageURL = workspaceImage ?? account.networkImgURL
            isWorkspaceImage = workspaceImage != nil
        } else {
            title = account.network
            subtitle = sharesNetwork ? Self.loginName(of: account) : nil
            imageURL = account.networkImgURL
            isWorkspaceImage = false
        }
    }

    /// A symbol for the network while its logo loads, or when its bridge
    /// publishes none.
    var systemImage: String {
        let bridge = bridgeID.lowercased().replacing("local-", with: "")
        switch bridge {
        case "whatsapp": return "phone.bubble.fill"
        case "telegram": return "paperplane.fill"
        case "signal": return "envelope.badge.shield.half.filled"
        case "discord", "discordgo": return "gamecontroller.fill"
        case "slack", "slackgo": return "square.grid.3x3.topleft.filled"
        case "instagram", "instagramgo": return "camera.fill"
        case "facebook", "facebookgo": return "bubble.left.and.bubble.right.fill"
        case "linkedin": return "person.text.rectangle.fill"
        case "hungryserv": return "circle.grid.hex.fill"
        case "twitter": return "x.squareroot"
        case "gmessages": return "message.fill"
        default: return "bubble.left.and.bubble.right"
        }
    }

    private static func loginName(of account: Account) -> String? {
        [account.loginName, account.user.username, account.user.fullName]
            .lazy
            .compactMap { $0?.trimmed }
            .first { !$0.isEmpty }
    }
}
