import SwiftUI

/// `NSCache` stores objects, so values are boxed.
private final class CacheBox<Value> {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Markdown parsing and link detection are costly enough to hitch scrolling,
/// and rows rebuild as they scroll into view, so cache by source text.
private let messageTextCache: NSCache<NSString, CacheBox<AttributedString>> = {
    let cache = NSCache<NSString, CacheBox<AttributedString>>()
    cache.countLimit = 2000
    return cache
}()

/// Block splitting is cached separately; most messages skip it entirely.
private let messageBlocksCache: NSCache<NSString, CacheBox<[MessageBlock]>> = {
    let cache = NSCache<NSString, CacheBox<[MessageBlock]>>()
    cache.countLimit = 500
    return cache
}()

/// Chat list previews churn less than timeline rows but rebuild on every
/// list update, so they get their own smaller cache.
private let previewTextCache: NSCache<NSString, CacheBox<AttributedString>> = {
    let cache = NSCache<NSString, CacheBox<AttributedString>>()
    cache.countLimit = 500
    return cache
}()

/// Characters that can start inline Markdown. Text without any of them
/// renders identically as plain text, so it skips parsing entirely.
private let inlineMarkdownMarkers: Set<Character> = ["*", "_", "~", "`", "[", "\\", "<", "&"]

/// A chat row shows at most two lines, so longer sources are cut before
/// parsing; anything past this is never visible.
private let previewSourceLimit = 400

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
        messageTextCache.setObject(CacheBox(attributed), forKey: key)
        return attributed
    }

    /// The message body split into blocks such as quotes. Each block's text
    /// goes through `messageAttributed`, so it shares that cache.
    var messageBlocks: [MessageBlock] {
        guard MessageBlockParser.mayContainBlocks(self) else { return [.text(messageAttributed)] }
        let key = self as NSString
        if let cached = messageBlocksCache.object(forKey: key) { return cached.value }
        var blocks = MessageBlockParser.blocks(in: self)
        // A body of bare markers (just ">") has no content; show it as typed.
        if blocks.isEmpty { blocks = [.text(messageAttributed)] }
        messageBlocksCache.setObject(CacheBox(blocks), forKey: key)
        return blocks
    }

    /// Inline Markdown for a chat list preview. Links keep their label but
    /// lose their destination so a tap selects the row instead of opening it.
    var previewAttributed: AttributedString {
        let source = utf8.count > previewSourceLimit ? String(prefix(previewSourceLimit)) : self
        guard source.contains(where: inlineMarkdownMarkers.contains) else { return AttributedString(source) }

        let key = source as NSString
        if let cached = previewTextCache.object(forKey: key) { return cached.value }
        var attributed = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
        attributed.link = nil
        previewTextCache.setObject(CacheBox(attributed), forKey: key)
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

            // A bare Matrix user link must retain its complete identity.
            var replacement = AttributedString(MessageMentionLink(destination)?.userID ?? destination.inlineDisplayLabel)
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
