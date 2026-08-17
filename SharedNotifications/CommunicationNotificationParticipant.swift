import Foundation

struct CommunicationNotificationParticipant: Sendable, Equatable {
    let id: String
    let name: String

    init?(userInfo: [String: Any]) {
        guard
            let id = userInfo["id"] as? String,
            id.isEmpty == false,
            let name = userInfo["name"] as? String,
            name.isEmpty == false
        else {
            return nil
        }
        self.id = id
        self.name = name
    }
}
