import SwiftUI

struct AttachmentView: View {
    let attachment: Attachment
    let message: Message
    let chat: Chat

    var body: some View {
        switch attachment.type {
        case .image:
            ImageAttachmentView(attachment: attachment, isOutgoing: message.isSender)
        case .video, .reel:
            VideoAttachmentView(attachment: attachment, message: message)
        case .audio:
            AudioAttachmentView(attachment: attachment, message: message, chat: chat)
        case .unknown, .none:
            FileAttachmentView(attachment: attachment, isOutgoing: message.isSender)
        }
    }
}
