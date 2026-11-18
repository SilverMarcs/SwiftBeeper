import SwiftUI

/// A formatting command for the composer, with Slack's shortcut for it. Each
/// one writes or removes Markdown around the selection, which the core sends
/// as formatted text.
enum ComposerFormat: CaseIterable {
    case bold
    case italic
    case strikethrough
    case code
    case codeBlock
    case link
    case quote
    case bulletedList
    case numberedList

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .code: "Code"
        case .codeBlock: "Code Block"
        case .link: "Link"
        case .quote: "Quote"
        case .bulletedList: "Bulleted List"
        case .numberedList: "Numbered List"
        }
    }

    /// The key, as typed without Shift or Option.
    var key: Character {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .strikethrough: "x"
        case .code, .codeBlock: "c"
        case .link: "u"
        case .quote: "9"
        case .bulletedList: "8"
        case .numberedList: "7"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .bold, .italic: .command
        case .codeBlock: [.command, .shift, .option]
        case .strikethrough, .code, .link, .quote, .bulletedList, .numberedList: [.command, .shift]
        }
    }
}
