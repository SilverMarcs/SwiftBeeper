import SwiftUI

extension View {
    /// A text style scaled by the chat's text size. macOS draws text styles
    /// at fixed sizes, ignoring `dynamicTypeSize`, so a scaled style is a
    /// system font at the style's size times `chatTextScale`. At the
    /// system's size it's the text style itself.
    func chatFont(_ style: Font.TextStyle, design: Font.Design? = nil) -> some View {
        modifier(ChatFont(style: style, design: design))
    }
}

private struct ChatFont: ViewModifier {
    let style: Font.TextStyle
    let design: Font.Design?
    @Environment(\.chatTextScale) private var scale

    func body(content: Content) -> some View {
        // The text style itself keeps iOS's Dynamic Type and macOS's own line
        // heights, which differ slightly from a sized font's. One expression,
        // so a zoom changes the font without rebuilding the text.
        content.font(scale == 1
            ? .system(style, design: design)
            : .system(size: style.macPointSize * scale, weight: style.macWeight, design: design))
    }
}

extension Font.TextStyle {
    /// The style's size on macOS, from `NSFont.preferredFont(forTextStyle:)`.
    var macPointSize: CGFloat {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }

    var macWeight: Font.Weight {
        switch self {
        case .headline: .bold
        case .caption2: .medium
        default: .regular
        }
    }
}
