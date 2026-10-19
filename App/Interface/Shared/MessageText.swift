import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
enum MessageText {
    static func attributed(_ text: String, message: Message?, chat: Chat, outgoing: Bool) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        let result = NSMutableAttributedString(parsed)
        let full = NSRange(location: 0, length: result.length)
        #if os(macOS)
        let font = NSFont.preferredFont(forTextStyle: .body)
        let color = outgoing ? NSColor.white : NSColor.labelColor
        let accent = outgoing ? NSColor.white : NSColor.controlAccentColor
        #else
        let font = UIFont.preferredFont(forTextStyle: .body)
        let color = outgoing ? UIColor.white : UIColor.label
        let accent = outgoing ? UIColor.white : UIColor.tintColor
        #endif
        result.addAttributes([.font: font, .foregroundColor: color], range: full)
        // Convert inline Markdown intent to the fonts used by native text systems.
        for run in parsed.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            let prefix = String(parsed.characters[..<run.range.lowerBound])
            let value = String(parsed.characters[run.range])
            let range = NSRange(location: prefix.utf16.count, length: value.utf16.count)
            #if os(macOS)
            var traits: NSFontTraitMask = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
            result.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: traits), range: range)
            #else
            var traits: UIFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { result.addAttribute(.font, value: UIFont(descriptor: descriptor, size: 0), range: range) }
            #endif
            if intent.contains(.strikethrough) { result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: result.string, range: full) {
                guard let url = match.url else { continue }
                result.addAttributes([.link: url, .foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: match.range)
            }
        }
        for mention in message?.mentions ?? [] {
            let participant = chat.participant(with: mention)
            for alias in [participant?.displayName, participant?.username, mention].compactMap({ $0 }) {
                let label = alias.hasPrefix("@") ? alias : "@" + alias
                let range = (result.string as NSString).range(of: label, options: .caseInsensitive)
                if range.location != NSNotFound { result.addAttribute(.foregroundColor, value: accent, range: range) }
            }
        }
        if message?.isDeletedMessage == true { result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: full) }
        return result
    }
}
