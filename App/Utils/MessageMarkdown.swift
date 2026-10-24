import SwiftUI

private final class AttributedStringBox {
    let value: AttributedString
    init(_ value: AttributedString) { self.value = value }
}

/// Markdown parsing and link detection are costly enough to hitch scrolling,
/// and rows rebuild as they scroll into view, so cache by source text.
private let messageTextCache: NSCache<NSString, AttributedStringBox> = {
    let cache = NSCache<NSString, AttributedStringBox>()
    cache.countLimit = 2000
    return cache
}()

private let sharedLinkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

extension String {
    /// Inline Markdown with bare URLs turned into compact, underlined links.
    /// Links take their color from the view's tint.
    var messageAttributed: AttributedString {
        let key = self as NSString
        if let cached = messageTextCache.object(forKey: key) { return cached.value }
        var attributed = (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
        attributed.condenseAndStyleLinks()
        messageTextCache.setObject(AttributedStringBox(attributed), forKey: key)
        return attributed
    }
}

private extension AttributedString {
    /// Turns bare URLs into links without moving them into separate bubbles.
    /// Long destinations keep their full target while displaying a compact
    /// host/path label. Existing Markdown links keep their authored label.
    mutating func condenseAndStyleLinks() {
        guard let detector = sharedLinkDetector else { return }

        let plainText = String(characters)
        let fullRange = NSRange(plainText.startIndex..., in: plainText)
        let matches = detector.matches(in: plainText, range: fullRange)

        for match in matches.reversed() {
            guard let destination = match.url,
                  let stringRange = Range(match.range, in: plainText),
                  let lowerBound = AttributedString.Index(stringRange.lowerBound, within: self),
                  let upperBound = AttributedString.Index(stringRange.upperBound, within: self) else {
                continue
            }

            let attributedRange = lowerBound..<upperBound
            // A Markdown link already has an authored label and destination.
            // Keep that label instead of replacing it with the detected text.
            if self[attributedRange].link != nil {
                continue
            }

            var replacement = AttributedString(destination.inlineDisplayLabel)
            replacement.link = destination
            replacement.underlineStyle = .single
            replaceSubrange(attributedRange, with: replacement)
        }

        // Underline authored Markdown links too.
        for run in runs where run.link != nil {
            self[run.range].underlineStyle = .single
        }
    }
}

private extension URL {
    /// A compact presentation label; the `link` attribute still retains the
    /// complete URL, including query parameters and fragments.
    var inlineDisplayLabel: String {
        var label = absoluteString.removingPercentEncoding ?? absoluteString
        if let scheme, label.lowercased().hasPrefix("\(scheme.lowercased())://") {
            label.removeFirst(scheme.count + 3)
        }
        if label.lowercased().hasPrefix("www.") {
            label.removeFirst(4)
        }

        let maximumLength = 48
        guard label.count > maximumLength else { return label }
        return "\(label.prefix(maximumLength - 1))…"
    }
}
