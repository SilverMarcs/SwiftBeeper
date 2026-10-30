import Foundation

struct ShareChatParticipant: Hashable, Decodable {
    let id: String
    let fullName: String?
    let username: String?
    let imgURL: String?
    let isSelf: Bool?

    var displayName: String {
        if let fullName, !fullName.isEmpty { return fullName }
        if let username, !username.isEmpty { return username }
        return id
    }
}
