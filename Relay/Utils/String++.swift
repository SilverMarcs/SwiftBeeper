//
//  String++.swift
//  SwiftBeeper
//
//  Created by Zabir Raihan on 05/03/2026.
//

import SwiftUI

extension Calendar {
    /// Shared calendar for display formatting. `Calendar.current` allocates a new
    /// value on every access; this cached, auto-updating instance avoids that in
    /// the hot path (message rows, timestamp dividers, sidebar rows).
    static let app = Calendar.autoupdatingCurrent
}

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

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }

    var extractedURLs: [URL] {
        guard let detector = sharedLinkDetector else {
            return []
        }
        let range = NSRange(startIndex..., in: self)
        return detector.matches(in: self, range: range).compactMap { $0.url }
    }
}
