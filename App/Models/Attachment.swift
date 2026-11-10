import Foundation

struct AttachmentSize: Codable, Equatable, Sendable {
    let width: Int?
    let height: Int?
}

/// The core's attachment type, keeping values this app doesn't know.
enum AttachmentKind: RawRepresentable, Codable, Equatable, Sendable {
    case image
    case video
    case reel
    case audio
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "img": self = .image
        case "video": self = .video
        case "reel": self = .reel
        case "audio": self = .audio
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .image: "img"
        case .video: "video"
        case .reel: "reel"
        case .audio: "audio"
        case .unknown(let value): value
        }
    }

    init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct Attachment: Identifiable, Codable, Equatable, Sendable {
    var id: String? { _id ?? srcURL ?? fileName }

    let type: AttachmentKind?
    let srcURL: String?
    let mimeType: String?
    let fileName: String?
    let fileSize: Int?
    let isGif: Bool?
    let duration: Double?
    let posterImg: String?
    let size: AttachmentSize?

    private let _id: String?

    private enum CodingKeys: String, CodingKey {
        case _id = "id"
        case type, srcURL, mimeType, fileName, fileSize
        case isGif, duration, posterImg, size
    }

    var resolvedURL: String? {
        srcURL ?? _id
    }

    /// The largest video the timeline downloads to play inline: 20 MB.
    static let maxInlineVideoSize = 20 * 1024 * 1024

    /// A video too large to download for inline playback, by its reported
    /// size. Videos without a size still play.
    var isTooLargeForInlinePlayback: Bool {
        guard type == .video || type == .reel, let fileSize else { return false }
        return fileSize > Self.maxInlineVideoSize
    }

    var typeLabel: String {
        switch type {
        case .image: "image"
        case .video, .reel: "video"
        case .audio: "audio"
        case .unknown, .none: "file"
        }
    }

    /// Short, title-case name for previews, such as "Photo" or "GIF".
    var previewLabel: String {
        switch type {
        case .image: isGif == true ? "GIF" : "Photo"
        case .video, .reel: "Video"
        case .audio: "Audio"
        case .unknown, .none:
            if let fileName = fileName?.trimmed, !fileName.isEmpty { fileName } else { "File" }
        }
    }

    /// Plural preview name for several attachments of this kind.
    var pluralPreviewLabel: String {
        switch type {
        case .image: "Photos"
        case .video, .reel: "Videos"
        case .audio: "Audio Files"
        case .unknown, .none: "Files"
        }
    }

    /// SF Symbol shown beside the preview label.
    var previewSymbol: String {
        switch type {
        case .image: "photo"
        case .video, .reel: "video"
        case .audio: "waveform"
        case .unknown, .none: "doc"
        }
    }
}
