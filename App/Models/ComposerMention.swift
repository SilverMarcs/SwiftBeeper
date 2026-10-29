import Foundation

/// UTF-16 offsets match the native text field and the core's wire format.
struct ComposerMention: Codable, Equatable, Sendable {
    let userID: String
    var location: Int
    let length: Int

    var range: NSRange { NSRange(location: location, length: length) }
}
