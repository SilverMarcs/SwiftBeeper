import SwiftUI

/// A group message's sender, in their colour, heading their run of bubbles.
struct SenderNameLabel: View {
    let message: Message

    var body: some View {
        Text(message.senderDisplayName)
            .bold()
            .foregroundStyle(IdentityColor(id: message.senderID).nameStyle)
    }
}
