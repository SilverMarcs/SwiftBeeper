import SwiftUI

struct AttachmentView: View {
    let attachment: Attachment
    let isOutgoing: Bool
    var chatTitle: String? = nil
    var avatarURL: String? = nil

    var body: some View {
        if attachment.isImage {
            ImageAttachmentView(attachment: attachment)
        } else if attachment.isVideo {
            VideoAttachmentView(attachment: attachment)
        } else if attachment.isAudio {
            AudioAttachmentView(attachment: attachment, isOutgoing: isOutgoing, title: chatTitle, avatarURL: avatarURL)
        } else {
            FileAttachmentView(attachment: attachment, isOutgoing: isOutgoing)
        }
    }
}
