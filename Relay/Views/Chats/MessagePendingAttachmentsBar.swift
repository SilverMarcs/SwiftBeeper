#if !os(macOS)
import SwiftUI

/// Shown on iPhone only while there are pending attachments. The iPhone uses
/// the navigation `.searchable` field for text and sending (return key), so
/// this transient bar just surfaces queued attachments — it is not a
/// persistent input bar and has no send button of its own.
struct MessagePendingAttachmentsBar: View {
    @Environment(InputManager.self) private var input

    var body: some View {
        if !input.pendingAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(input.pendingAttachments) { pending in
                        PendingAttachmentPreview(
                            pending: pending,
                            isSending: input.isSendingMessage,
                            onRemove: { input.removePendingAttachment(id: pending.id) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}
#endif
