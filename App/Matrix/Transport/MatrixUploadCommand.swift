import Foundation

nonisolated struct MatrixUploadCommand: Encodable {
    let action = "stage-upload"
    let path: String
    let fileName: String
    let mimeType: String
}
