import Foundation

enum AttachmentUploadError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): "Upload failed: \(message)"
        }
    }
}
