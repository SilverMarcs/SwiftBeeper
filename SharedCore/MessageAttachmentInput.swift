import Foundation

struct MessageAttachmentInput: Encodable {
    let uploadID: String
    let mimeType: String?
    let fileName: String?
    let size: AttachmentSizeInput?
}
