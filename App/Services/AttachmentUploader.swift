import Foundation

/// Prepares composer attachments and stages them with the Matrix core.
enum AttachmentUploader {
    static func upload(
        _ attachment: PendingAttachment,
        onPrepared: (PendingAttachment) -> Void = { _ in },
        onProgress: @escaping @MainActor @Sendable (Double) -> Void = { _ in }
    ) async throws -> MessageAttachmentInput {
        let prepared = await ImageAttachmentPreparer.prepare(attachment)
        try Task.checkCancellation()
        onPrepared(prepared)
        let result = try await APIClient.uploadAsset(
            fileData: prepared.fileData,
            fileName: prepared.fileName,
            mimeType: prepared.mimeType,
            onProgress: onProgress
        )
        if let error = result.error, !error.isEmpty {
            throw AttachmentUploadError.server(error)
        }
        onProgress(1)
        let size: AttachmentSizeInput?
        if let width = result.width, let height = result.height {
            size = AttachmentSizeInput(width: width, height: height)
        } else {
            size = nil
        }
        return MessageAttachmentInput(
            uploadID: result.uploadID,
            mimeType: prepared.mimeType,
            fileName: prepared.fileName,
            size: size,
            duration: result.duration,
            type: nil
        )
    }
}
