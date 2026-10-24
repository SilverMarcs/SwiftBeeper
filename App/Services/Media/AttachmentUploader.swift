import Foundation

/// Prepares composer attachments and stages them with the Matrix core.
enum AttachmentUploader {
    /// `onPrepared` receives the attachment as it will be sent (possibly
    /// recompressed) before the upload starts.
    static func upload(
        _ attachment: PendingAttachment,
        onPrepared: (PendingAttachment) -> Void = { _ in }
    ) async throws -> MessageAttachmentInput {
        let prepared = await ImageAttachmentPreparer.prepare(attachment)
        try Task.checkCancellation()
        onPrepared(prepared)
        let result = try await APIClient.uploadAsset(
            fileData: prepared.fileData,
            fileName: prepared.fileName,
            mimeType: prepared.mimeType
        )
        let size: AttachmentSizeInput? = if let width = result.width, let height = result.height {
            AttachmentSizeInput(width: width, height: height)
        } else {
            nil
        }
        return MessageAttachmentInput(
            uploadID: result.uploadID,
            mimeType: prepared.mimeType,
            fileName: prepared.fileName,
            size: size
        )
    }
}
