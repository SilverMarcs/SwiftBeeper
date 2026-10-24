/// Changing from a placeholder to a video restarts the task while preserving
/// the attachment view's Play intent and its continuous loading indicator.
enum VideoAttachmentRequest: Hashable {
    case resolve(String)
    case play(String)
}
