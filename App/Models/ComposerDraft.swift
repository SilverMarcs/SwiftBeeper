import Foundation

/// Tracks identities through ordinary text edits without guessing from names.
struct ComposerDraft {
    var text = ""
    var mentions: [ComposerMention] = []

    var trimmed: Self {
        var result = self
        result.updateText(text.trimmed)
        return result
    }

    mutating func updateText(_ newText: String) {
        guard newText != text else { return }
        let prefix = zip(text, newText).prefix(while: { $0 == $1 }).count
        let oldTail = text.dropFirst(prefix)
        let newTail = newText.dropFirst(prefix)
        let suffix = zip(oldTail.reversed(), newTail.reversed()).prefix(while: { $0 == $1 }).count
        let start = text.prefix(prefix).utf16.count
        let end = text.dropLast(suffix).utf16.count
        let delta = newText.utf16.count - text.utf16.count

        mentions = mentions.compactMap { mention in
            var mention = mention
            if start == end, start == mention.location + mention.length,
               let next = newTail.first, next.isLetter || next.isNumber || next == "_" {
                return nil
            }
            if mention.location >= end {
                mention.location += delta
            } else if mention.location + mention.length > start {
                return nil
            }
            return mention
        }
        text = newText
    }

    /// Restores linked identities when an existing message enters Edit.
    init(message: Message) {
        guard let formatted = message.formattedText,
              let attributed = try? AttributedString(
                markdown: formatted,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              ) else {
            text = message.text ?? ""
            return
        }
        text = String(attributed.characters)
        for run in attributed.runs {
            guard let url = run.link, let link = MessageMentionLink(url),
                  let range = Range(run.range, in: text) else { continue }
            let nativeRange = NSRange(range, in: text)
            mentions.append(ComposerMention(userID: link.userID, location: nativeRange.location, length: nativeRange.length))
        }
    }

    init() {}
}
