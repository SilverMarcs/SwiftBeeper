import Foundation

/// A bridge's latest report on an outgoing message.
enum MessageDeliveryStatus: String, Codable, Sendable {
    /// The bridge handed it to the network.
    case sent
    /// The recipient's device confirmed it. Only direct chats on networks
    /// with delivery receipts, such as WhatsApp, report this.
    case delivered
    /// The network didn't take it.
    case failed
}
