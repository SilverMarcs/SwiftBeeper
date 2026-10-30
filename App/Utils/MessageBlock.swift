import Foundation

/// A top-level piece of a message body. Most messages are a single `.text`;
/// block syntax splits the body so each block can draw its own chrome.
///
/// To support another block (code, list), add a case here, recognize it in
/// `MessageBlockParser`, and draw it in `MessageBlockView`.
enum MessageBlock {
    /// Inline Markdown, rendered as one `Text`.
    case text(AttributedString)
    /// `>` lines. Their content is parsed again, so quotes can nest.
    case quote([MessageBlock])
}
