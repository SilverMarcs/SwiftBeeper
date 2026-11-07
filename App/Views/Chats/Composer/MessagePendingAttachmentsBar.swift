import SwiftUI

/// The composer's queued attachments, shown only while there are some. On
/// iPhone it sits above the navigation `.searchable` field, which sends.
struct MessagePendingAttachmentsBar: View {
    let composer: Composer

    var body: some View {
        if !composer.pendingAttachments.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(composer.pendingAttachments) { pending in
                        PendingAttachmentPreview(pending: pending) {
                            composer.pendingAttachments.removeAll { $0.id == pending.id }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }
}
