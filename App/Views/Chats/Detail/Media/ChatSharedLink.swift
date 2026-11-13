import Foundation

/// One link from a chat message, for the links list.
struct ChatSharedLink: Identifiable {
    let url: URL
    let message: Message

    var id: String { "\(message.id) \(url.absoluteString)" }

    /// Each message's links, in order.
    static func links(in messages: some Sequence<Message>) -> [ChatSharedLink] {
        messages.flatMap { message in
            message.linkURLs.map { ChatSharedLink(url: $0, message: message) }
        }
    }

    /// The message's text, when it says more than the link itself.
    var context: String? {
        guard let text = message.visibleText, text != url.absoluteString else { return nil }
        return text
    }
}
