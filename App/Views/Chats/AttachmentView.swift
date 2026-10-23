import SwiftUI

struct AttachmentView: View {
    let attachment: Attachment
    let message: Message
    let chat: Chat

    var body: some View {
        if attachment.isImage {
            ImageAttachmentView(attachment: attachment)
        } else if attachment.isVideo {
            VideoAttachmentView(attachment: attachment)
        } else if attachment.isAudio {
            AudioAttachmentView(attachment: attachment, message: message, chat: chat)
        } else {
            FileAttachmentView(attachment: attachment, isOutgoing: message.isSender)
        }
    }
}
