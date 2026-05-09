//
//  String++.swift
//  SwiftBeeper
//
//  Created by Zabir Raihan on 05/03/2026.
//

import SwiftUI

extension String {
    var markdownAttributed: AttributedString {
        (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
    }
    
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }

    var extractedURLs: [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(startIndex..., in: self)
        return detector.matches(in: self, range: range).compactMap { $0.url }
    }
}
