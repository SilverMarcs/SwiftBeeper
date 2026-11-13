import SwiftUI

/// A search result's text as one line of context: starting shortly before
/// the first searched word, so a match deep in a long message still shows,
/// with every searched word bold.
enum MessageSearchSnippet {
    /// Characters kept before the first match.
    private static let leadingContext = 24

    static func text(_ text: String, query: String) -> AttributedString {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        var snippet = Substring(flattened)
        let firstMatch = words.compactMap {
            flattened.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])?.lowerBound
        }.min()
        if let firstMatch, flattened.distance(from: flattened.startIndex, to: firstMatch) > leadingContext {
            var start = flattened.index(firstMatch, offsetBy: -leadingContext)
            // Begin at a word.
            if let space = flattened[start..<firstMatch].firstIndex(where: \.isWhitespace) {
                start = flattened.index(after: space)
            }
            snippet = "…" + flattened[start...]
        }

        var attributed = AttributedString(snippet)
        for word in words {
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                attributed[range].inlinePresentationIntent = .stronglyEmphasized
                attributed[range].foregroundColor = .primary
                searchStart = range.upperBound
            }
        }
        return attributed
    }
}
