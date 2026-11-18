import Foundation

/// A stretch of the draft with a Markdown meaning, which the composer styles
/// so the draft looks as it will be sent.
struct ComposerMarkdownSpan: Equatable {
    enum Kind: Equatable {
        /// Markup that won't show once sent, such as `**` or a link's URL.
        case syntax
        case bold
        case italic
        case strikethrough
        /// Inline code.
        case code
        /// A fenced or indented code block's lines.
        case codeBlock
        /// A quote's text.
        case quote
        case heading
        /// A link's label.
        case link
        /// A list item's bullet or number, which becomes the list's marker.
        case listMarker
        /// A whole line of a quote, markers included.
        case quoteLine
    }

    let kind: Kind
    let range: NSRange
    /// For markup that's hidden until needed: the construct it belongs to,
    /// such as a bold word with its `**`s. The markup shows while the
    /// selection touches it, so it can be edited. Nil markup always shows.
    var reveal: NSRange?
}
