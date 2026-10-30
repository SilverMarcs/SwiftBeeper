import Foundation

/// What the share sheet handed over: at most one file, plus any links or text
/// to start the message with.
struct SharedContent {
    var attachment: PendingAttachment?
    var text = ""
}
