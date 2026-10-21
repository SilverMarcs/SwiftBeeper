//
//  String++.swift
//  Relay
//
//  Created by Zabir Raihan on 05/03/2026.
//

import SwiftUI

private final class AttributedStringBox {
    let value: AttributedString
    init(_ value: AttributedString) { self.value = value }
}

/// Parsed markdown is identical for identical input, but parsing runs on every
/// `body` re-evaluation. Cache by source string so re-renders are cheap.
private let markdownCache: NSCache<NSString, AttributedStringBox> = {
    let cache = NSCache<NSString, AttributedStringBox>()
    cache.countLimit = 2000
    return cache
}()

/// Cache the finished Markdown and link presentation for each bubble style.
private let messageTextCache: NSCache<NSString, AttributedStringBox> = {
    let cache = NSCache<NSString, AttributedStringBox>()
    cache.countLimit = 2000
    return cache
}()

private let sharedLinkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

extension String {
    var markdownAttributed: AttributedString {
        let key = self as NSString
        if let cached = markdownCache.object(forKey: key) { return cached.value }
        let parsed = (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
        markdownCache.setObject(AttributedStringBox(parsed), forKey: key)
        return parsed
    }

    func messageAttributed(isOutgoing: Bool) -> AttributedString {
        let key = "\(isOutgoing)\u{1E}\(self)" as NSString
        if let cached = messageTextCache.object(forKey: key) { return cached.value }
        var attributed = markdownAttributed
        attributed.condenseAndStyleLinks(isOutgoing: isOutgoing)
        messageTextCache.setObject(AttributedStringBox(attributed), forKey: key)
        return attributed
    }
}

private extension AttributedString {
    /// Turns bare URLs into links without moving them into separate bubbles.
    /// Long destinations keep their full target while displaying a compact
    /// host/path label. Existing Markdown links keep their authored label.
    mutating func condenseAndStyleLinks(isOutgoing: Bool) {
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
            replacement.foregroundColor = isOutgoing ? .white : .blue
            replacement.underlineStyle = .single
            replaceSubrange(attributedRange, with: replacement)
        }

        // Style authored Markdown links as well as the bare links inserted
        // above. Outgoing bubbles use white for contrast on the accent fill.
        for run in runs where run.link != nil {
            self[run.range].foregroundColor = isOutgoing ? .white : .blue
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
