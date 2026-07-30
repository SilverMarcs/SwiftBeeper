#if os(iOS)
import Foundation

struct CommunicationNotificationParticipant: Sendable, Equatable {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init?(userInfo: [String: Any]) {
        guard
            let id = userInfo["id"] as? String,
            id.isEmpty == false,
            let name = userInfo["name"] as? String,
            name.isEmpty == false
        else {
            return nil
        }
        self.init(id: id, name: name)
    }
}
#endif
