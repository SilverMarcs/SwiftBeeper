import SwiftUI

/// The shared item's preview, an optional message, and Send.
struct ShareComposer: View {
    @Bindable var model: ShareModel

    var body: some View {
        VStack(alignment: .leading) {
            if let attachment = model.attachment {
                ShareAttachmentPreview(attachment: attachment, image: model.attachmentPreview)
            }
            HStack {
                TextField("Add a message", text: $model.text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                ShareSendButton(model: model)
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.bar)
    }
}
