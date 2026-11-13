import Foundation

/// The Slack-style team one login belongs to.
struct AccountWorkspace: Decodable, Hashable {
    let id: String
    let name: String
    /// The team's icon, published by the bridge on the workspace's space.
    let imgURL: String?
}
