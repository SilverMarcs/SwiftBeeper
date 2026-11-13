import Foundation

/// The caption below the user's messages and the message it follows: their
/// newest message, which in a group needn't be the chat's newest.
struct DeliveryCaption: Equatable {
    let indicator: DeliveryIndicator
    let messageID: Message.ID
}
