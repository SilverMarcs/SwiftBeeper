import Foundation

struct UploadAssetOutput: Decodable {
    let uploadID: String
    let srcURL: String?
    let fileName: String?
    let mimeType: String?
    let fileSize: Int?
    let width: Int?
    let height: Int?
    let duration: Double?
    let error: String?
}

struct MessageAttachmentInput: Encodable {
    let uploadID: String
    let mimeType: String?
    let fileName: String?
    let size: AttachmentSizeInput?
    let duration: Double?
    let type: String?
}

struct AttachmentSizeInput: Encodable {
    let width: Int
    let height: Int
}

struct PendingAttachment: Identifiable, Equatable {
    let id: UUID
    let fileData: Data
    let fileName: String
    let mimeType: String

    init(id: UUID = UUID(), fileData: Data, fileName: String, mimeType: String) {
        self.id = id
        self.fileData = fileData
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

struct AttachmentSize: Decodable, Equatable {
    let width: Int?
    let height: Int?
}

enum AttachmentKind: RawRepresentable, Decodable, Equatable {
    case image
    case video
    case audio
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "img":
            self = .image
        case "video":
            self = .video
        case "audio":
            self = .audio
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .image:
            return "img"
        case .video:
            return "video"
        case .audio:
            return "audio"
        case .unknown(let value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = AttachmentKind(rawValue: try container.decode(String.self))
    }
}

struct Attachment: Identifiable, Decodable, Equatable {
    var id: String? { _id ?? srcURL ?? fileName }

    let type: AttachmentKind?
    let srcURL: String?
    let mimeType: String?
    let fileName: String?
    let fileSize: Int?
    let isGif: Bool?
    let isSticker: Bool?
    let isVoiceNote: Bool?
    let duration: Double?
    let posterImg: String?
    let size: AttachmentSize?

    private let _id: String?

    private enum CodingKeys: String, CodingKey {
        case _id = "id"
        case type, srcURL, mimeType, fileName, fileSize
        case isGif, isSticker, isVoiceNote, duration, posterImg, size
    }

    var isImage: Bool { type == .image }
    var isVideo: Bool { type == .video }
    var isAudio: Bool { type == .audio }

    var resolvedURL: String? {
        srcURL ?? _id
    }

    var typeLabel: String {
        if isImage { return "image" }
        if isVideo { return "video" }
        if isAudio { return "audio" }
        return "file"
    }
}
