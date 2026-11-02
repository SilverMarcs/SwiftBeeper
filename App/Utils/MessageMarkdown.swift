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
    /// host/path label. Markdown links with an authored label keep it.
    mutating func condenseAndStyleLinks() {
        condenseBareLinkLabels()

        if let detector = sharedLinkDetector {
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
                // Already a link, either authored or autolinked by the
                // Markdown parser and condensed above.
                if self[attributedRange].link != nil {
                    continue
                }

                var replacement = AttributedString(destination.compactLinkLabel)
                replacement.link = destination
                replaceSubrange(attributedRange, with: replacement)
            }
        }

        for run in runs where run.link != nil {
            self[run.range].underlineStyle = .single
        }
    }

    /// The Markdown parser autolinks bare URLs itself, labelling them with the
    /// full URL. Those labels, and `[url](url)` links, get the compact label;
    /// links with a distinct authored label are left alone.
    mutating func condenseBareLinkLabels() {
        var bareLinks: [(range: Range<AttributedString.Index>, url: URL)] = []
        for (link, range) in runs[\.link] {
            guard let link else { continue }
            let label = String(self[range].characters)
            if link.isLabelledByItself(label) {
                bareLinks.append((range, link))
            }
        }

        for bareLink in bareLinks.reversed() {
            let attributes = self[bareLink.range].runs.first?.attributes ?? AttributeContainer()
            var replacement = AttributedString(bareLink.url.compactLinkLabel, attributes: attributes)
            replacement.link = bareLink.url
            replaceSubrange(bareLink.range, with: replacement)
        }
    }
}

private extension URL {
    /// The label shown for a link whose text is just its URL. A Matrix user
    /// link keeps its complete user ID; anything else gets a compact form.
    var compactLinkLabel: String {
        MessageMentionLink(self)?.userID ?? inlineDisplayLabel
    }

    /// Whether `label` is this URL written out, with or without its scheme
    /// or percent-encoding, as opposed to an authored description.
    func isLabelledByItself(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let candidates = [absoluteString, absoluteString.removingPercentEncoding].compactMap(\.self)
        return candidates.contains { candidate in
            candidate == trimmed || candidate.withoutScheme == trimmed.withoutScheme
        }
    }

    /// A compact presentation label: host and path, without the scheme,
    /// `www.`, query or fragment. The `link` attribute still retains the
    /// complete URL, so tapping opens the original destination.
    var inlineDisplayLabel: String {
        guard let host = host(), scheme == "http" || scheme == "https" else {
            return truncatedLinkLabel(absoluteString.removingPercentEncoding ?? absoluteString)
        }

        var label = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let decodedPath = path(percentEncoded: false)
        if decodedPath != "/" {
            label += decodedPath
        }
        if label.hasSuffix("/") {
            label.removeLast()
        }
        return truncatedLinkLabel(label)
    }

    private func truncatedLinkLabel(_ label: String) -> String {
        let maximumLength = 40
        guard label.count > maximumLength else { return label }
        return "\(label.prefix(maximumLength - 1))…"
    }
}

private extension String {
    /// The string with any leading `scheme://` removed, for comparing a link
    /// label to its URL.
    var withoutScheme: Substring {
        guard let separator = range(of: "://") else { return self[...] }
        return self[separator.upperBound...]
    }
}
