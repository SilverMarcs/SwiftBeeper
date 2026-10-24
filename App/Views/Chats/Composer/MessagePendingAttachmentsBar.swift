import SwiftUI

/// The composer's queued attachments, shown only while there are some. On
/// iPhone it sits above the navigation `.searchable` field, which sends.
struct MessagePendingAttachmentsBar: View {
    @Environment(InputManager.self) private var input

    var body: some View {
        if !input.pendingAttachments.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(input.pendingAttachments) { pending in
                        PendingAttachmentPreview(pending: pending)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }
}
