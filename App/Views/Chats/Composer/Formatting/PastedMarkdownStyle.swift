#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The formatting of one character of pasted rich text, as far as the
/// composer's Markdown can write it.
struct PastedMarkdownStyle: Equatable {
    var bold = false
    var italic = false
    var strikethrough = false
    /// Set in a fixed-pitch font, which pastes as code.
    var code = false
    /// A web or mail address the text links to.
    var link: String?

    init() {}

    init(_ attributes: [NSAttributedString.Key: Any]) {
        #if canImport(AppKit)
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            bold = traits.contains(.bold) || Self.weight(of: font.fontDescriptor.object(forKey: .traits)) >= Self.boldWeight
            italic = traits.contains(.italic)
            code = font.isFixedPitch || traits.contains(.monoSpace)
        }
        #else
        if let font = attributes[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            bold = traits.contains(.traitBold) || Self.weight(of: font.fontDescriptor.object(forKey: .traits)) >= Self.boldWeight
            italic = traits.contains(.traitItalic)
            code = traits.contains(.traitMonoSpace)
        }
        #endif
        if let obliqueness = attributes[.obliqueness] as? NSNumber, obliqueness.doubleValue != 0 {
            italic = true
        }
        if let strike = attributes[.strikethroughStyle] as? NSNumber, strike.intValue != 0 {
            strikethrough = true
        }
        link = Self.address(attributes[.link])
    }

    /// Semibold and heavier read as bold.
    private static let boldWeight = 0.3

    private static func weight(of traits: Any?) -> Double {
        #if canImport(AppKit)
        let weight = (traits as? [NSFontDescriptor.TraitKey: Any])?[.weight]
        #else
        let weight = (traits as? [UIFontDescriptor.TraitKey: Any])?[.weight]
        #endif
        return (weight as? NSNumber)?.doubleValue ?? 0
    }

    /// Web and mail links only; app links, such as a chat app's mentions,
    /// mean nothing once sent.
    private static func address(_ value: Any?) -> String? {
        let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
        guard let address = url?.absoluteString, ComposerMarkdownEdit.isURL(address) else { return nil }
        return address
    }
}
