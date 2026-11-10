import Foundation

/// A top-level piece of a message body. Most messages are a single `.text`;
/// block syntax splits the body so each block can draw its own chrome.
///
/// To support another block, add a case here, recognize it in
/// `MessageBlockParser`, and draw it in `MessageBlockView`.
enum MessageBlock {
    /// Inline Markdown, rendered as one `Text`.
    case text(AttributedString)
    /// `>` lines. Their content is parsed again, so quotes can nest.
    case quote([MessageBlock])
    /// `#` to `######` lines; level 1 is the largest.
    case heading(level: Int, AttributedString)
    /// Bulleted or numbered items, each with its own blocks, so lists nest.
    case list([MessageListItem])
    /// A fenced code block, shown verbatim.
    case code(String)
    /// A `---` line.
    case rule
}
