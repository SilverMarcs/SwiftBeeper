import SwiftUI

extension EnvironmentValues {
    /// Set on a macOS message body once its text is selectable, so its text
    /// blocks draw one `Text` per line; see `MessageTextLines`.
    @Entry var drawsMessageTextLines = false
}

/// A text block drawn as one `Text` per line, stacked with no spacing.
///
/// Selectable text on macOS lays out a line after a line break about a point
/// lower than plain `Text` does, so a body that becomes selectable as the
/// pointer reaches it would visibly jump below its first break. Lines without
/// breaks lay out identically either way, and stacked they match the plain
/// body exactly. An empty line keeps its height but isn't selectable, so a
/// copied selection doesn't pick up stray spaces.
struct MessageTextLines: View {
    let text: AttributedString

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(text.messageLines.enumerated(), id: \.offset) { _, line in
                if line.characters.isEmpty {
                    Text(verbatim: " ").hidden()
                } else {
                    Text(line)
                }
            }
        }
    }
}

private extension AttributedString {
    /// The text split at its line breaks, which aren't included.
    var messageLines: [AttributedString] {
        var lines: [AttributedString] = []
        var start = startIndex
        var index = startIndex
        while index < endIndex {
            let next = characters.index(after: index)
            if characters[index] == "\n" {
                lines.append(AttributedString(self[start..<index]))
                start = next
            }
            index = next
        }
        lines.append(AttributedString(self[start..<endIndex]))
        return lines
    }
}
