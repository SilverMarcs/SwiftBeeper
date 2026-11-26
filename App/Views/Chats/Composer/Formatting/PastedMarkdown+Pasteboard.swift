#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers

extension PastedMarkdown {
    #if canImport(AppKit)
    /// The rich text on the pasteboard as Markdown, or nil when it has none
    /// worth keeping.
    static func markdown(from pasteboard: NSPasteboard) -> String? {
        markdown { pasteboard.data(forType: NSPasteboard.PasteboardType($0.identifier)) }
    }
    #else
    /// The rich text on the pasteboard as Markdown, or nil when it has none
    /// worth keeping.
    static func markdown(from pasteboard: UIPasteboard) -> String? {
        markdown { pasteboard.data(forPasteboardType: $0.identifier) }
    }
    #endif

    /// Rich text types, best first; HTML is slowest to import.
    private static let richTextTypes: [(UTType, NSAttributedString.DocumentType)] = [
        (.flatRTFD, .rtfd), (.rtf, .rtf), (.html, .html),
    ]

    private static func markdown(readingData data: (UTType) -> Data?) -> String? {
        for (type, documentType) in richTextTypes {
            // Text this long pastes as plain text anyway.
            guard let data = data(type), data.count <= maximumLength * 20 else { continue }
            var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: documentType]
            if documentType == .html {
                options[.characterEncoding] = String.Encoding.utf8.rawValue
            }
            guard let text = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else { continue }
            return markdown(from: text)
        }
        return nil
    }
}
