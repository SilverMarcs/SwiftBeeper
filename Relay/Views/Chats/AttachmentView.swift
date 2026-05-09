import SwiftUI

struct AttachmentView: View {
    let attachment: Attachment
    let isOutgoing: Bool

    var body: some View {
        if attachment.isImage {
            ImageAttachmentView(attachment: attachment)
        } else if attachment.isVideo {
            VideoAttachmentView(attachment: attachment)
        } else if attachment.isAudio {
            AudioAttachmentView(attachment: attachment, isOutgoing: isOutgoing)
        } else {
            FileAttachmentView(attachment: attachment, isOutgoing: isOutgoing)
        }
    }
}
