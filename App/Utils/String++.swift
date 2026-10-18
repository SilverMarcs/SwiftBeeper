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

/// Mention styling does a small amount of Unicode-aware scanning. Cache the
/// finished value independently from the base Markdown cache so scrolling and
/// unrelated observation updates don't repeat that work.
private let messageTextCache: NSCache<NSString, AttributedStringBox> = {
    let cache = NSCache<NSString, AttributedStringBox>()
    cache.countLimit = 2000
    return cache
}()

/// Creating an `NSDataDetector` is relatively expensive; share one instance.
private let sharedLinkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

extension String {
    var markdownAttributed: AttributedString {
        let key = self as NSString
        if let cached = markdownCache.object(forKey: key) {
            return cached.value
        }
        let parsed = (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
        markdownCache.setObject(AttributedStringBox(parsed), forKey: key)
        return parsed
    }

    /// Renders message Markdown, compact inline links, and non-interactive
    /// highlighted @mentions.
    ///
    /// Beeper supplies participant IDs for current messages, but legacy
    /// messages have a nil `mentions` field and require text scanning. Known
    /// IDs are resolved to participant usernames and display names so mentions
    /// containing spaces are styled as one range.
    func messageAttributed(
        mentionIDs: [String]?,
        participants: [ChatParticipant],
        isOutgoing: Bool
    ) -> AttributedString {
        let aliasesByID = (mentionIDs ?? []).map { mentionID in
            let participant = participants.first(where: { $0.id == mentionID })
            let aliases = [
                mentionID,
                participant?.username,
                participant?.fullName
            ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .map(Self.mentionLabel)
                .uniqued()
            return (mentionID, aliases)
        }
        let metadataKey = mentionIDs.map { $0.sorted().joined(separator: "\u{1F}") } ?? "<legacy>"
        let aliasesKey = aliasesByID
            .flatMap(\.1)
            .sorted()
            .joined(separator: "\u{1F}")
        let cacheKey = "\(isOutgoing)\u{1E}\(metadataKey)\u{1E}\(aliasesKey)\u{1E}\(self)" as NSString

        if let cached = messageTextCache.object(forKey: cacheKey) {
            return cached.value
        }

        var attributed = markdownAttributed
        attributed.condenseAndStyleLinks(isOutgoing: isOutgoing)
        var requiresTextScanning = mentionIDs == nil

        for (_, aliases) in aliasesByID {
            var foundAlias = false
            for alias in aliases {
                let ranges = attributed.mentionRanges(of: alias)
                foundAlias = foundAlias || !ranges.isEmpty
                for range in ranges {
                    attributed.styleMention(in: range, isOutgoing: isOutgoing)
                }
            }
            requiresTextScanning = requiresTextScanning || !foundAlias
        }

        if requiresTextScanning {
            for range in attributed.scannedMentionRanges() {
                attributed.styleMention(in: range, isOutgoing: isOutgoing)
            }
        }

        messageTextCache.setObject(AttributedStringBox(attributed), forKey: cacheKey)
        return attributed
    }

    nonisolated private static func mentionLabel(_ value: String) -> String {
        value.hasPrefix("@") ? value : "@\(value)"
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
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

    func mentionRanges(of label: String) -> [Range<AttributedString.Index>] {
        var result: [Range<AttributedString.Index>] = []
        var searchStart = startIndex

        while searchStart < endIndex,
              let range = self[searchStart...].range(of: label, options: [.caseInsensitive]) {
            let hasValidLeadingBoundary: Bool
            if range.lowerBound == startIndex {
                hasValidLeadingBoundary = true
            } else {
                let previousIndex = characters.index(before: range.lowerBound)
                hasValidLeadingBoundary = !characters[previousIndex].isMentionCore
            }

            let hasValidTrailingBoundary = range.upperBound == endIndex
                || !characters[range.upperBound].isMentionCore

            if hasValidLeadingBoundary && hasValidTrailingBoundary {
                result.append(range)
            }
            searchStart = range.upperBound
        }

        return result
    }

    func scannedMentionRanges() -> [Range<AttributedString.Index>] {
        var result: [Range<AttributedString.Index>] = []
        var index = startIndex

        while index < endIndex {
            guard characters[index] == "@" else {
                index = characters.index(after: index)
                continue
            }

            if index != startIndex {
                let previousIndex = characters.index(before: index)
                if characters[previousIndex].isMentionCore {
                    index = characters.index(after: index)
                    continue
                }
            }

            let contentStart = characters.index(after: index)
            guard contentStart < endIndex, characters[contentStart].isMentionCore else {
                index = contentStart
                continue
            }

            var mentionEnd = characters.index(after: contentStart)
            while mentionEnd < endIndex, characters[mentionEnd].isMentionContinuation {
                mentionEnd = characters.index(after: mentionEnd)
            }

            while mentionEnd > contentStart {
                let lastIndex = characters.index(before: mentionEnd)
                guard characters[lastIndex] == "." || characters[lastIndex] == "-" else { break }
                mentionEnd = lastIndex
            }

            result.append(index..<mentionEnd)
            index = mentionEnd
        }

        return result
    }

    mutating func styleMention(in range: Range<AttributedString.Index>, isOutgoing: Bool) {
        self[range].foregroundColor = isOutgoing ? .white : .accentColor
        var intent = self[range].inlinePresentationIntent ?? []
        intent.insert(.stronglyEmphasized)
        self[range].inlinePresentationIntent = intent
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

private extension Character {
    var isMentionCore: Bool {
        isLetter || isNumber || self == "_"
    }

    var isMentionContinuation: Bool {
        isMentionCore || self == "." || self == "-"
    }
}
