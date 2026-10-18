import Foundation

nonisolated struct ChatPaginationCursor: Encodable {
    let ts: Int64
    let room_id: String

    static func encode(_ chat: Chat?) -> String? {
        guard let chat, let date = chat.lastActivity else { return nil }
        let cursor = Self(ts: Int64((date.timeIntervalSince1970 * 1000).rounded()), room_id: chat.id)
        return (try? JSONEncoder().encode(cursor))?.base64EncodedString()
            .replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
    }
}
