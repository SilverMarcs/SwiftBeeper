import Foundation

/// A file picked, pasted, or shared into the composer, not yet uploaded.
struct PendingAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let fileData: Data
    let fileName: String
    let mimeType: String

    nonisolated init(id: UUID = UUID(), fileData: Data, fileName: String, mimeType: String) {
        self.id = id
        self.fileData = fileData
        self.fileName = fileName
        self.mimeType = mimeType
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
