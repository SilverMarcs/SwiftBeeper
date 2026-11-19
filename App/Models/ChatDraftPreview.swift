import Foundation

/// A chat's unsent draft as the chat list shows it: an attachment symbol
/// when the draft carries attachments, then its text, which may be empty.
struct ChatDraftPreview: Equatable {
    var text: String
    var symbol: String?
}
